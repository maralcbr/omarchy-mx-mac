#!/bin/bash

set -euo pipefail

fail() {
  echo "build-app: $*" >&2
  exit 1
}

usage() {
  echo "usage: build-app.sh RELEASE_DIRECTORY OUTPUT_DIRECTORY" >&2
  exit 64
}

[[ $# -eq 2 ]] || usage

script_directory="$({ cd "$(dirname "$0")" && pwd -P; })"
package_directory="$({ cd "$script_directory/.." && pwd -P; })"
release_directory="$({ cd "$1" && pwd -P; })"
output_directory="$2"

[[ -d $release_directory && ! -L $release_directory ]] \
  || fail "release directory must be a real directory"
[[ $output_directory == /* ]] \
  || output_directory="$package_directory/$output_directory"

build_jobs="${OMARCHY_BUILD_JOBS:-10}"
[[ $build_jobs =~ ^[1-9][0-9]*$ ]] \
  || fail "OMARCHY_BUILD_JOBS must be a positive integer"
export CARGO_BUILD_JOBS="$build_jobs"

marketing_version="${OMARCHY_APP_VERSION:-0.1.0}"
build_number="${OMARCHY_APP_BUILD_NUMBER:-1}"
signing_identity="${OMARCHY_APP_SIGNING_IDENTITY:--}"
team_identifier="${OMARCHY_TEAM_ID:-}"

[[ $marketing_version =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9]+)*$ ]] \
  || fail "OMARCHY_APP_VERSION has an invalid format"
[[ $build_number =~ ^[1-9][0-9]*$ ]] \
  || fail "OMARCHY_APP_BUILD_NUMBER must be a positive integer"

app_identifier="com.omarchy.mx.installer"
helper_identifier="com.omarchy.mx.installer.helper"
app_name="Omarchy MX Mac Installer.app"
app_executable_name="OmarchyAppleInstallerApp"
helper_executable_name="omarchy-apple-installer-helper"
daemon_plist_name="$helper_identifier.plist"
engine_file_name="installer-v0.9.0-omarchy.2.tar.gz"
engine_digest="09eefcb25ba434f084a3b1e0700c3277629f67f1d3514f59bddd6107a39dfde5"

if [[ $signing_identity == "-" ]]; then
  client_requirement="identifier \"$app_identifier\""
  helper_requirement="identifier \"$helper_identifier\""
  timestamp_arguments=(--timestamp=none)
else
  [[ $team_identifier =~ ^[A-Z0-9]{10}$ ]] \
    || fail "OMARCHY_TEAM_ID is required for named signing identities"
  client_requirement="anchor apple generic and identifier \"$app_identifier\" and certificate leaf[subject.OU] = \"$team_identifier\""
  helper_requirement="anchor apple generic and identifier \"$helper_identifier\" and certificate leaf[subject.OU] = \"$team_identifier\""
  if [[ $signing_identity == Developer\ ID\ Application:* ]]; then
    timestamp_arguments=(--timestamp)
  else
    timestamp_arguments=(--timestamp=none)
  fi
fi

release_descriptor="$release_directory/release.json"
trust_root="$release_directory/trust-root.ed25519.pub"
[[ -f $release_descriptor && ! -L $release_descriptor ]] \
  || fail "release.json is missing or unsafe"
[[ -f $trust_root && ! -L $trust_root ]] \
  || fail "trust-root.ed25519.pub is missing or unsafe"
(( $(stat -f %z "$release_descriptor") <= 65536 )) \
  || fail "release.json exceeds 65536 bytes"
(( $(stat -f %z "$trust_root") == 32 )) \
  || fail "trust-root.ed25519.pub must contain exactly 32 bytes"

descriptor_schema="$(plutil -extract schema_version raw -o - "$release_descriptor")"
descriptor_service="$(plutil -extract helper_mach_service_name raw -o - "$release_descriptor")"
descriptor_requirement="$(plutil -extract helper_code_signing_requirement raw -o - "$release_descriptor")"
descriptor_fingerprint="$(plutil -extract trust_root_fingerprint raw -o - "$release_descriptor")"
[[ $descriptor_schema == "1" ]] \
  || fail "release.json schema_version must be 1"
[[ $descriptor_service == $helper_identifier ]] \
  || fail "release.json helper service does not match the compiled product"
[[ $descriptor_requirement == $helper_requirement ]] \
  || fail "release.json helper signing requirement does not match this build"
actual_fingerprint="sha256:$(shasum -a 256 "$trust_root" | awk '{print $1}')"
[[ $descriptor_fingerprint == $actual_fingerprint ]] \
  || fail "release.json trust root fingerprint does not match the public key"

engine_source="$package_directory/Engine/artifacts/$engine_file_name"
[[ -f $engine_source && ! -L $engine_source ]] \
  || fail "the pinned validation engine artifact is missing"
actual_engine_digest="$(shasum -a 256 "$engine_source" | awk '{print $1}')"
[[ $actual_engine_digest == $engine_digest ]] \
  || fail "the pinned validation engine digest is incorrect"

mkdir -p "$output_directory"
final_app="$output_directory/$app_name"
[[ ! -e $final_app ]] \
  || fail "refusing to overwrite existing app: $final_app"

swift_tool="$(xcrun --find swift)"
(
  cd "$package_directory"
  "$swift_tool" build \
    --configuration release \
    --jobs "$build_jobs"
)
binary_directory="$({
  cd "$package_directory"
  "$swift_tool" build --configuration release --show-bin-path
})"

app_binary="$binary_directory/$app_executable_name"
helper_binary="$binary_directory/OmarchyAppleInstallerHelper"
[[ -x $app_binary ]] || fail "app executable was not built"
[[ -x $helper_binary ]] || fail "helper executable was not built"

assembly_root="$(mktemp -d "$output_directory/.omarchy-app.XXXXXX")"
trap 'rm -rf "$assembly_root"' EXIT
assembled_app="$assembly_root/$app_name"
contents="$assembled_app/Contents"
resources="$contents/Resources"

mkdir -p \
  "$contents/MacOS" \
  "$resources/Release" \
  "$resources/Engine/artifacts" \
  "$contents/Library/LaunchDaemons"

install -m 0755 "$app_binary" "$contents/MacOS/$app_executable_name"
install -m 0755 "$helper_binary" "$resources/$helper_executable_name"
install -m 0444 "$release_descriptor" "$resources/Release/release.json"
install -m 0444 "$trust_root" "$resources/Release/trust-root.ed25519.pub"
install -m 0444 "$engine_source" "$resources/Engine/artifacts/$engine_file_name"
install -m 0444 "$script_directory/Info.plist" "$contents/Info.plist"
install -m 0444 \
  "$script_directory/$daemon_plist_name" \
  "$contents/Library/LaunchDaemons/$daemon_plist_name"

chmod 0644 "$contents/Info.plist"
chmod 0644 "$contents/Library/LaunchDaemons/$daemon_plist_name"
plutil -replace CFBundleShortVersionString \
  -string "$marketing_version" "$contents/Info.plist"
plutil -replace CFBundleVersion \
  -string "$build_number" "$contents/Info.plist"
plutil -replace \
  EnvironmentVariables.OMARCHY_CLIENT_CODE_SIGNING_REQUIREMENT \
  -string "$client_requirement" \
  "$contents/Library/LaunchDaemons/$daemon_plist_name"
plutil -lint \
  "$contents/Info.plist" \
  "$contents/Library/LaunchDaemons/$daemon_plist_name" >/dev/null

codesign --force --sign "$signing_identity" \
  "${timestamp_arguments[@]}" \
  --options runtime \
  --identifier "$helper_identifier" \
  "$resources/$helper_executable_name"
codesign --force --sign "$signing_identity" \
  "${timestamp_arguments[@]}" \
  --options runtime \
  "$assembled_app"

codesign --verify --deep --strict --verbose=2 "$assembled_app"
codesign --verify --strict \
  -R="$helper_requirement" \
  "$resources/$helper_executable_name"
codesign --verify --strict \
  -R="$client_requirement" \
  "$assembled_app"

mv "$assembled_app" "$final_app"
echo "$final_app"
