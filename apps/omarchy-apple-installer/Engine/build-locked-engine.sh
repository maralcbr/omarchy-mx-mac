#!/bin/bash

set -euo pipefail

if (( $# != 3 )); then
  echo "Usage: build-locked-engine.sh CHECKOUT INPUT_CACHE OUTPUT_DIRECTORY" >&2
  exit 1
fi

checkout=$(cd "$1" && pwd -P)
input_cache=$(cd "$2" && pwd -P)
mkdir -p "$3"
output_directory=$(cd "$3" && pwd -P)
engine_root=$(cd "${BASH_SOURCE[0]%/*}" && pwd -P)
lock="$engine_root/source-lock.json"
build_jobs=${OMARCHY_BUILD_JOBS:-10}

if [[ ! $build_jobs =~ ^[1-9][0-9]*$ ]]; then
  echo "OMARCHY_BUILD_JOBS must be a positive integer" >&2
  exit 1
fi
export CARGO_BUILD_JOBS="$build_jobs"

python3 "$engine_root/verify-source-lock.py" "$checkout"

require_exact() {
  local actual=$1 expected=$2 name=$3
  if [[ $actual != "$expected" ]]; then
    echo "$name does not match source lock" >&2
    echo "expected: $expected" >&2
    echo "actual:   $actual" >&2
    exit 1
  fi
}

tool_path() {
  jq -r --arg name "$1" '.build_toolchain.tools[$name].path' "$lock"
}

tool_version() {
  jq -r --arg name "$1" '.build_toolchain.tools[$name].version' "$lock"
}

clang=$(tool_path clang)
lld=$(tool_path lld)
rustc=$(tool_path rustc)
cargo=$(tool_path cargo)
make_tool=$(tool_path make)
bsdtar=$(tool_path bsdtar)
cpio=$(tool_path cpio)
gtar=$(tool_path gtar)
gzip=$(tool_path gzip)
seven_zip=$(tool_path seven_zip)

require_exact "$($clang --version | head -1)" "$(tool_version clang)" clang
require_exact "$($lld --version | head -1)" "$(tool_version lld)" lld
require_exact "$($rustc --version)" "$(tool_version rustc)" rustc
require_exact "$($cargo --version)" "$(tool_version cargo)" cargo
require_exact "$($make_tool --version | head -1)" "$(tool_version make)" make
require_exact "$($bsdtar --version | head -1)" "$(tool_version bsdtar)" bsdtar
require_exact "$($cpio --version | head -1)" "$(tool_version cpio)" cpio
require_exact "$($gtar --version | head -1)" "$(tool_version gtar)" gtar
require_exact "$($gzip --version | head -1)" "$(tool_version gzip)" gzip
require_exact "$($seven_zip 2>&1 | head -2 | tail -1)" "$(tool_version seven_zip)" seven_zip

target=$(jq -r '.build_toolchain.rust_target' "$lock")
if [[ ! -d $($rustc --print target-libdir --target "$target") ]]; then
  echo "Locked Rust target is not installed: $target" >&2
  exit 1
fi

while IFS=$'\t' read -r filename size expected; do
  path="$input_cache/$filename"
  if [[ ! -f $path ]]; then
    echo "Locked build input missing: $path" >&2
    exit 1
  fi
  actual_size=$(stat -f '%z' "$path")
  if [[ ! $size =~ ^[0-9]+$ ]]; then
    echo "Locked build input size is invalid: $path" >&2
    exit 1
  fi
  if (( actual_size != size )); then
    echo "Locked build input size mismatch: $path" >&2
    exit 1
  fi
  actual=$(/usr/bin/shasum -a 256 "$path")
  actual=${actual%% *}
  if [[ $actual != "$expected" ]]; then
    echo "Locked build input digest mismatch: $path" >&2
    exit 1
  fi
done < <(
  jq -r '.build_inputs[] | [.filename, .size_bytes, .sha256] | @tsv' "$lock"
)

stage=$(mktemp -d /private/tmp/omarchy-locked-engine-build.XXXXXX)
trap 'rm -rf -- "$stage"' EXIT
cp -a "$checkout/." "$stage/"
git -C "$stage" apply "$engine_root/$(jq -r '.downstream_overlay.patch.path' "$lock")"

while IFS=$'\t' read -r source destination; do
  mkdir -p "$stage/${destination%/*}"
  cp "$engine_root/$source" "$stage/$destination"
done < <(
  jq -r '.downstream_overlay.files[] | [.path, .destination] | @tsv' "$lock"
)

metadata=$(jq -r '.downstream_overlay.metadata.path' "$lock")
cp "$engine_root/$metadata" "$stage/installer_data.json"
version=$(jq -r '.downstream_overlay.version' "$lock")
printf '%s\n' "$version" >"$stage/version.tag"

mkdir -p "$stage/dl"
while IFS= read -r filename; do
  cp "$input_cache/$filename" "$stage/dl/$filename"
done < <(jq -r '.build_inputs[].filename' "$lock")

PYTHONPATH="$stage/src" python3 -m unittest discover \
  -s "$stage/tests" -p 'test_omarchy_*.py'
python3 -m py_compile "$stage/src/main.py" "$stage/src"/omarchy_*.py

PATH="${cargo%/*}:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$make_tool" -C "$stage/m1n1" RELEASE=1 CHAINLOADING=1 -j"$build_jobs"

mv "$stage/.git" "$stage/.provenance.git"
PATH="${cargo%/*}:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  M1N1_STAGE1="$stage/m1n1/build/m1n1.bin" "$stage/build.sh"

cp "$stage/installer_data.json" "$stage/package/installer_data.json"
certificate="$stage/package/Frameworks/Python.framework/Versions/Current/etc/openssl/cert.pem"
chmod u+w "$certificate"
cp "$stage/dl/certifi-cacert-2026.07.22.pem" "$certificate"
chmod 444 "$certificate"
find "$stage/package" -type d -name __pycache__ -prune -exec rm -rf -- {} +
find "$stage/package" \( -type f -o -type d \) -exec chmod go-w {} +

artifact="$output_directory/installer-$version.tar.gz"
temporary=$(mktemp "$output_directory/.installer.XXXXXX")
source_date_epoch=$(jq -r '.build_toolchain.source_date_epoch' "$lock")
"$gtar" --sort=name --format=pax \
  --pax-option=delete=atime,delete=ctime \
  --mtime="@$source_date_epoch" --owner=0 --group=0 --numeric-owner \
  -C "$stage/package" -cf - . | "$gzip" -n -9 >"$temporary"
chmod 644 "$temporary"
mv -f "$temporary" "$artifact"
python3 "$engine_root/verify-archive-modes.py" "$artifact"

actual_size=$(stat -f '%z' "$artifact")
actual_digest=$(/usr/bin/shasum -a 256 "$artifact")
actual_digest=${actual_digest%% *}
expected_filename=$(jq -er '.validation_artifact.filename' "$lock")
expected_size=$(jq -er '.validation_artifact.size_bytes' "$lock")
expected_digest=$(jq -er '.validation_artifact.sha256' "$lock")
if [[ ${artifact##*/} != "$expected_filename" ]]; then
  echo "Built engine filename does not match source lock" >&2
  exit 1
fi
[[ $expected_size =~ ^[1-9][0-9]*$ ]] || {
  echo "Expected engine size is invalid" >&2
  exit 1
}
if (( actual_size != expected_size )); then
  echo "Built engine size does not reproduce source lock" >&2
  exit 1
fi
if [[ ! $expected_digest =~ ^[0-9a-f]{64}$ ]]; then
  echo "Expected engine digest is invalid" >&2
  exit 1
fi
if [[ $actual_digest != "$expected_digest" ]]; then
  echo "Built engine digest does not reproduce source lock" >&2
  exit 1
fi
printf '%s  %s  %s bytes\n' "$actual_digest" "$artifact" "$actual_size"
