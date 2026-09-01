#!/bin/bash

# E2E pre-clean for the M1 (macOS side), driven over the pinned Thunderbolt
# SSH alias.
#
# What it does:
#   1. Proves it is talking to the expected machine.
#   2. Reads the LIVE disk0 layout and the LIVE APFS container list.
#   3. Identifies the protected partitions from those live values —
#      the macOS Apple_APFS store carrying the "Macintosh HD" volume group,
#      the Apple_APFS_Recovery partition, and the Apple_APFS_ISC partition.
#      Anything ambiguous is a HARD ABORT.
#   4. Identifies the Omarchy partitions by TYPE and NAME.
#   5. Prints the complete deletion plan.
#   6. Only with --confirm: deletes every Omarchy APFS container, then frees
#      each Omarchy partition BY UUID, then clears the installer's staging/state
#      and removes old installer copies.
#
# Multiple Omarchy installs (repeated test installs) are supported: every APFS
# container holding an "Omarchy" volume, every "EFI - OMARC" ESP, and every
# Linux filesystem partition is planned. A container that claims to hold both
# an Omarchy volume and "Macintosh HD" is a HARD ABORT.
#
# Without --confirm it changes nothing. It never touches Macintosh HD, the
# Recovery partition, the ISC partition, or any user data.
#
# Testing hook: set OMARCHY_PRECLEAN_SSH_SHIM to an executable that receives
# (operation, command) and prints canned output. When it is set, no ssh is run.

set -uo pipefail

readonly DEFAULT_HOST="omarchy-m1-thunderbolt"
readonly EXPECTED_USER="mina"
readonly EXPECTED_MODEL="MacBookPro18,3"
readonly EXPECTED_BRIDGE_IP="10.77.0.2"
readonly EXPECTED_INTERFACE="bridge0"
readonly OMARCHY_EFI_NAME="EFI - OMARC"
readonly OMARCHY_VOLUME_NAME="Omarchy"
readonly MACOS_VOLUME_NAME="Macintosh HD"
readonly APP_SUPPORT_ID="com.omarchy.mx.installer"
readonly APP_BUNDLE_NAME="Omarchy MX Mac Installer.app"

# Volume names and partition types that must never appear in a deletion plan.
readonly PROTECTED_NAME_PATTERN='^(Macintosh HD|Macintosh HD - Data|Recovery|Preboot|VM|Update|xART|iSCPreboot|Hardware)$'
readonly PROTECTED_TYPE_PATTERN='^(Apple_APFS_Recovery|Apple_APFS_ISC|Apple_boot|Apple_KernelCoreDump)$'

host="$DEFAULT_HOST"
confirm="no"
dry_run="no"
skip_partitions="no"
skip_macos="no"
work=""
actions_taken=0

usage() {
  cat >&2 <<'USAGE'
Usage:
  preclean-m1.sh [--dry-run] [--confirm] [--host ALIAS]
                 [--skip-partitions] [--skip-macos-cleanup]

Default behaviour is a dry run: the plan is printed and nothing is changed.
--confirm is the only thing that lets a destructive command run.

  --dry-run              explicit no-op mode (the default); refuses --confirm
  --confirm              actually perform the printed plan
  --host ALIAS           ssh alias for the M1 (default: omarchy-m1-thunderbolt)
  --skip-partitions      leave the disk alone; only clean staging/state/apps
  --skip-macos-cleanup   only the partitions; leave staging/state/apps alone
  -h, --help             this text

Environment:
  OMARCHY_PRECLEAN_SSH_SHIM   test hook. When set, this executable is called as
                              "$SHIM <operation> <command>" instead of ssh.
USAGE
  exit 64
}

die() {
  echo >&2
  echo "preclean-m1: HARD ABORT: $*" >&2
  exit 1
}

note() {
  echo "preclean-m1: $*"
}

heading() {
  echo
  echo "== $* =="
}

cleanup() {
  [[ -z $work ]] || rm -rf "$work"
}

# ---------------------------------------------------------------------------
# Remote execution
# ---------------------------------------------------------------------------

remote() {
  local operation=$1 command=$2
  # Detached stdin on both paths: several callers run inside while-read
  # loops, and a remote command that reads stdin silently consumes the
  # remaining loop input (ssh's default behavior).
  if [[ -n ${OMARCHY_PRECLEAN_SSH_SHIM:-} ]]; then
    "$OMARCHY_PRECLEAN_SSH_SHIM" "$operation" "$command" </dev/null
    return $?
  fi
  ssh -n -T -o BatchMode=yes "$host" "$command"
}

# Every destructive command funnels through here. Without --confirm it is only
# echoed. Nothing else in this script is allowed to write to the M1.
remote_destructive() {
  local operation=$1 command=$2
  if [[ $confirm != "yes" ]]; then
    echo "  WOULD RUN: $command"
    return 0
  fi
  echo "  RUNNING:   $command"
  remote "$operation" "$command"
  local status=$?
  if (( status != 0 )); then
    die "$operation failed with status $status; stopping before any further destructive step"
  fi
  actions_taken=$((actions_taken + 1))
  return 0
}

# ---------------------------------------------------------------------------
# Remote command bodies (quoted heredocs — nothing expands locally)
# ---------------------------------------------------------------------------

identity_command() {
  cat <<'REMOTE'
/usr/bin/id -un
/usr/sbin/system_profiler SPHardwareDataType | /usr/bin/awk -F': ' '/Model Identifier/ { print $2 }'
REMOTE
}

partitions_command() {
  cat <<'REMOTE'
for slice in $(/usr/sbin/diskutil list /dev/disk0 | /usr/bin/awk '$NF ~ /^disk0s[0-9]+$/ { print $NF }'); do
  /usr/sbin/diskutil info "$slice" | /usr/bin/awk -v id="$slice" '
    /Partition Type:/ { line = $0; sub(/^ *Partition Type: */, "", line); type = line }
    /Volume Name:/ { line = $0; sub(/^ *Volume Name: */, "", line); name = line }
    /Partition UUID:/ { line = $0; sub(/^.*Partition UUID: */, "", line); uuid = line }
    /Disk Size:/ {
      if (bytes == "" && match($0, /\(([0-9]+) Bytes\)/)) {
        bytes = substr($0, RSTART + 1, RLENGTH - 8)
      }
    }
    END {
      if (name ~ /^Not applicable/ || name == "") { name = "-" }
      printf "%s\t%s\t%s\t%s\t%s\n", id, type, name, uuid, bytes
    }
  '
done
REMOTE
}

containers_command() {
  cat <<'REMOTE'
/usr/sbin/diskutil apfs list | /usr/bin/awk '
  function flush() {
    if (ref != "") { printf "%s\t%s\t%s\t%s\t%s\n", ref, uuid, store, storeuuid, names }
    ref = ""; uuid = ""; store = ""; storeuuid = ""; names = ""
  }
  /^\+-- Container disk/ {
    flush()
    line = $0
    sub(/^\+-- Container */, "", line)
    n = split(line, field, " ")
    ref = field[1]
    uuid = field[2]
  }
  /Physical Store disk/ {
    line = $0
    sub(/^.*Physical Store */, "", line)
    n = split(line, field, " ")
    if (n >= 2 && field[1] ~ /^disk[0-9]+s[0-9]+$/) {
      store = field[1]
      storeuuid = field[2]
    }
  }
  {
    line = $0
    sub(/^[ |+<>-]*/, "", line)
    if (line ~ /^Name: /) {
      sub(/^Name: */, "", line)
      sub(/ +\(Case-.*$/, "", line)
      names = (names == "") ? line : names "," line
    }
  }
  END { flush() }
'
REMOTE
}

app_support_command() {
  cat <<'REMOTE'
base="$HOME/Library/Application Support/com.omarchy.mx.installer"
if [ -d "$base" ] && [ ! -L "$base" ]; then
  /usr/bin/du -sk "$base" | /usr/bin/awk -v p="$base" '{ printf "present\t%s\t%s\n", $1, p }'
else
  printf 'absent\t0\t%s\n' "$base"
fi
REMOTE
}

old_apps_command() {
  cat <<'REMOTE'
for candidate in \
  "/Applications/Omarchy MX Mac Installer.app" \
  "$HOME/Downloads/Omarchy MX Mac Installer.app" \
  "$HOME/Downloads/__MACOSX"
do
  if [ -e "$candidate" ] && [ ! -L "$candidate" ]; then
    printf '%s\n' "$candidate"
  fi
done
/usr/bin/find "$HOME/Downloads" -maxdepth 1 -type f -name 'Omarchy-MX-Mac-Installer-*.zip' -print 2>/dev/null
REMOTE
}

# ---------------------------------------------------------------------------
# Discovery
# ---------------------------------------------------------------------------

verify_local_route() {
  [[ -z ${OMARCHY_PRECLEAN_SSH_SHIM:-} ]] || return 0
  local interface
  interface=$(
    /sbin/route -n get "$EXPECTED_BRIDGE_IP" 2>/dev/null |
      /usr/bin/awk '/interface:/ { print $2 }'
  )
  [[ $interface == "$EXPECTED_INTERFACE" ]] ||
    die "route to $EXPECTED_BRIDGE_IP is via '${interface:-none}', expected $EXPECTED_INTERFACE"
  note "route to $EXPECTED_BRIDGE_IP is $EXPECTED_INTERFACE"
}

verify_identity() {
  local output user model
  output=$(remote identity "$(identity_command)") ||
    die "cannot reach $host over ssh"
  user=$(printf '%s\n' "$output" | sed -n '1p' | tr -d '[:space:]')
  model=$(printf '%s\n' "$output" | sed -n '2p' | sed 's/^ *//; s/ *$//')
  [[ $user == "$EXPECTED_USER" ]] ||
    die "remote user is '$user', expected '$EXPECTED_USER'"
  [[ $model == "$EXPECTED_MODEL" ]] ||
    die "remote model is '$model', expected '$EXPECTED_MODEL'"
  note "peer verified: $user@$host is a $model"
}

read_partitions() {
  remote partitions "$(partitions_command)" >"$work/partitions.tsv" ||
    die "cannot read the disk0 partition table"
  [[ -s $work/partitions.tsv ]] || die "the disk0 partition table came back empty"
  local count
  count=$(grep -c '' "$work/partitions.tsv")
  note "read $count partitions from disk0"
}

read_containers() {
  remote containers "$(containers_command)" >"$work/containers.tsv" ||
    die "cannot read the APFS container list"
  [[ -s $work/containers.tsv ]] || die "the APFS container list came back empty"
  local count
  count=$(grep -c '' "$work/containers.tsv")
  note "read $count APFS containers"
}

partition_field() {
  local uuid=$1 column=$2
  awk -F '\t' -v uuid="$uuid" -v column="$column" \
    '$4 == uuid { print $column; exit }' "$work/partitions.tsv"
}

partition_uuid_for_identifier() {
  awk -F '\t' -v id="$1" '$1 == id { print $4; exit }' "$work/partitions.tsv"
}

is_protected_uuid() {
  [[ -s $work/protected.txt ]] || return 1
  grep -qxF "$1" "$work/protected.txt"
}

add_protected() {
  local uuid=$1 reason=$2
  [[ -n $uuid ]] || die "cannot protect an empty UUID ($reason)"
  printf '%s\n' "$uuid" >>"$work/protected.txt"
  printf '  PROTECTED  %-10s %-22s %s\n' \
    "$(awk -F '\t' -v u="$uuid" '$4 == u { print $1; exit }' "$work/partitions.tsv")" \
    "$reason" "$uuid"
}

identify_protected() {
  : >"$work/protected.txt"

  # macOS: exactly one APFS container whose volumes include "Macintosh HD".
  local macos_stores macos_store macos_count
  macos_stores=$(
    awk -F '\t' -v name="$MACOS_VOLUME_NAME" '
      index("," $5 ",", "," name ",") > 0 { print $3 }
    ' "$work/containers.tsv"
  )
  macos_count=$(printf '%s' "$macos_stores" | grep -c '.')
  (( macos_count == 1 )) ||
    die "expected exactly one APFS container holding a '$MACOS_VOLUME_NAME' volume, found $macos_count — the layout is ambiguous, refusing to plan any deletion"
  macos_store=$(printf '%s\n' "$macos_stores" | head -1)
  local macos_uuid
  macos_uuid=$(partition_uuid_for_identifier "$macos_store")
  [[ -n $macos_uuid ]] ||
    die "the macOS physical store '$macos_store' has no partition UUID in the live table"
  local macos_type
  macos_type=$(partition_field "$macos_uuid" 2)
  [[ $macos_type == "Apple_APFS" ]] ||
    die "the macOS physical store '$macos_store' is type '$macos_type', expected Apple_APFS"
  add_protected "$macos_uuid" "macOS ($macos_store)"

  # Recovery: exactly one Apple_APFS_Recovery partition.
  local recovery_uuids recovery_count uuid
  recovery_uuids=$(
    awk -F '\t' '$2 == "Apple_APFS_Recovery" { print $4 }' "$work/partitions.tsv"
  )
  recovery_count=$(printf '%s' "$recovery_uuids" | grep -c '.')
  (( recovery_count == 1 )) ||
    die "expected exactly one Apple_APFS_Recovery partition, found $recovery_count — refusing to plan any deletion"
  add_protected "$(printf '%s\n' "$recovery_uuids" | head -1)" "Recovery"

  # Everything else Apple reserves: ISC, Apple_boot, core dumps.
  while IFS= read -r uuid; do
    [[ -n $uuid ]] || continue
    is_protected_uuid "$uuid" && continue
    add_protected "$uuid" "Apple reserved"
  done <<EOF
$(awk -F '\t' -v pattern="$PROTECTED_TYPE_PATTERN" \
    '$2 ~ pattern { print $4 }' "$work/partitions.tsv")
EOF

  # Any partition carrying a protected volume name, whatever its type.
  while IFS= read -r uuid; do
    [[ -n $uuid ]] || continue
    is_protected_uuid "$uuid" && continue
    add_protected "$uuid" "protected volume name"
  done <<EOF
$(awk -F '\t' -v pattern="$PROTECTED_NAME_PATTERN" \
    '$3 ~ pattern { print $4 }' "$work/partitions.tsv")
EOF
}

identify_omarchy() {
  : >"$work/targets.tsv"
  : >"$work/container.tsv"

  # A container claiming to hold both an Omarchy volume and macOS would make
  # every later decision unsafe. Refuse outright.
  local conflicted
  conflicted=$(
    awk -F '\t' -v want="$OMARCHY_VOLUME_NAME" -v macos="$MACOS_VOLUME_NAME" '
      index("," $5 ",", "," want ",") > 0 &&
      index("," $5 ",", "," macos ",") > 0 { print $1 }
    ' "$work/containers.tsv"
  )
  [[ -z $conflicted ]] ||
    die "container $conflicted holds both an '$OMARCHY_VOLUME_NAME' volume and '$MACOS_VOLUME_NAME' — refusing to plan any deletion"

  # The Omarchy stubs: every APFS container holding an "Omarchy" volume that is
  # not the macOS container. Repeated test installs leave one stub each.
  local rows count
  rows=$(
    awk -F '\t' -v want="$OMARCHY_VOLUME_NAME" -v macos="$MACOS_VOLUME_NAME" '
      index("," $5 ",", "," want ",") > 0 &&
      index("," $5 ",", "," macos ",") == 0 { print }
    ' "$work/containers.tsv"
  )
  count=$(printf '%s' "$rows" | grep -c '.')
  if (( count > 0 )); then
    printf '%s\n' "$rows" >"$work/container.tsv"
    local ref cuuid store storeuuid names store_uuid
    while IFS=$'\t' read -r ref cuuid store storeuuid names; do
      [[ -n $ref ]] || continue
      store_uuid=$(partition_uuid_for_identifier "$store")
      [[ -n $store_uuid ]] ||
        die "the Omarchy physical store '$store' has no partition UUID in the live table"
      printf '%s\t%s\n' "$store_uuid" "Omarchy APFS stub store" >>"$work/target-uuids.tsv"
    done <"$work/container.tsv"
    note "found $count Omarchy APFS container(s)"
  fi

  # The Omarchy ESP, matched on its distinctive volume name.
  local uuid
  while IFS= read -r uuid; do
    [[ -n $uuid ]] || continue
    printf '%s\t%s\n' "$uuid" "Omarchy ESP" >>"$work/target-uuids.tsv"
  done <<EOF
$(awk -F '\t' -v name="$OMARCHY_EFI_NAME" '$3 == name { print $4 }' "$work/partitions.tsv")
EOF

  # The Omarchy boot and root partitions.
  while IFS= read -r uuid; do
    [[ -n $uuid ]] || continue
    printf '%s\t%s\n' "$uuid" "Omarchy Linux filesystem" >>"$work/target-uuids.tsv"
  done <<EOF
$(awk -F '\t' '$2 == "Linux Filesystem" { print $4 }' "$work/partitions.tsv")
EOF

  [[ -f $work/target-uuids.tsv ]] || : >"$work/target-uuids.tsv"

  # Guard every candidate before it is allowed into the plan.
  local role type name identifier size
  while IFS=$'\t' read -r uuid role; do
    [[ -n $uuid ]] || continue
    is_protected_uuid "$uuid" &&
      die "candidate $uuid ($role) is also on the protected list — refusing to delete anything"
    identifier=$(partition_field "$uuid" 1)
    type=$(partition_field "$uuid" 2)
    name=$(partition_field "$uuid" 3)
    size=$(partition_field "$uuid" 5)
    [[ -n $identifier ]] ||
      die "candidate $uuid ($role) is not in the live partition table"
    [[ ! $name =~ $PROTECTED_NAME_PATTERN ]] ||
      die "candidate $identifier carries the protected volume name '$name'"
    [[ ! $type =~ $PROTECTED_TYPE_PATTERN ]] ||
      die "candidate $identifier is a protected partition type '$type'"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$identifier" "$type" "$name" "$uuid" "$size" "$role" >>"$work/targets.tsv"
  done <"$work/target-uuids.tsv"

  # Duplicate UUIDs would mean the same partition is planned twice.
  local unique total
  total=$(grep -c '' "$work/targets.tsv")
  unique=$(cut -f 4 <"$work/targets.tsv" | LC_ALL=C sort -u | grep -c '.')
  (( total == unique )) ||
    die "the deletion plan lists $total entries but only $unique distinct partitions"
}

read_macos_cleanup_candidates() {
  remote app-support "$(app_support_command)" >"$work/app-support.tsv" ||
    die "cannot inspect the installer's Application Support directory"
  remote old-apps "$(old_apps_command)" >"$work/old-apps.txt"
  [[ -f $work/old-apps.txt ]] || : >"$work/old-apps.txt"
}

# ---------------------------------------------------------------------------
# Plan and execution
# ---------------------------------------------------------------------------

print_plan() {
  heading "Live disk0 layout on $host"
  printf '  %-9s %-22s %-24s %-38s %s\n' IDENT TYPE NAME "PARTITION UUID" BYTES
  local identifier type name uuid size
  while IFS=$'\t' read -r identifier type name uuid size; do
    printf '  %-9s %-22s %-24s %-38s %s\n' \
      "$identifier" "$type" "$name" "$uuid" "$size"
  done <"$work/partitions.tsv"

  heading "Protected — these are never touched"
  local reason
  while IFS= read -r uuid; do
    [[ -n $uuid ]] || continue
    printf '  %-9s %-22s %-24s %s\n' \
      "$(partition_field "$uuid" 1)" \
      "$(partition_field "$uuid" 2)" \
      "$(partition_field "$uuid" 3)" \
      "$uuid"
  done <"$work/protected.txt"

  heading "Deletion plan"
  if [[ ! -s $work/targets.tsv ]]; then
    echo "  No Omarchy partitions found. Nothing to erase."
  else
    local step=1
    if [[ -s $work/container.tsv ]]; then
      local ref cuuid store storeuuid names
      while IFS=$'\t' read -r ref cuuid store storeuuid names; do
        [[ -n $ref ]] || continue
        echo "  $step. Delete the Omarchy APFS container $ref ($cuuid), physical store $store."
        step=$((step + 1))
      done <"$work/container.tsv"
    fi
    echo "  $step. Free each partition below BY UUID (identifiers shift as space is"
    echo "     released, UUIDs do not — that is why UUIDs are used):"
    while IFS=$'\t' read -r identifier type name uuid size reason; do
      printf '     %-9s %-22s %-24s %-38s %-13s %s\n' \
        "$identifier" "$type" "$name" "$uuid" "$size" "$reason"
    done <"$work/targets.tsv"
  fi

  heading "macOS-side cleanup plan"
  if [[ $skip_macos == "yes" ]]; then
    echo "  skipped (--skip-macos-cleanup)"
  else
    local state size path
    IFS=$'\t' read -r state size path <"$work/app-support.tsv"
    if [[ $state == "present" ]]; then
      echo "  Remove installer staging + scratch + state + handoff:"
      echo "    $path (${size} KiB)"
    else
      echo "  Installer staging/state directory is already absent."
    fi
    if [[ -s $work/old-apps.txt ]]; then
      echo "  Remove old installer copies:"
      while IFS= read -r path; do
        [[ -n $path ]] || continue
        echo "    $path"
      done <"$work/old-apps.txt"
    else
      echo "  No old installer copies found in /Applications or ~/Downloads."
    fi
  fi
}

erase_partitions() {
  heading "Erasing Omarchy partitions"
  if [[ ! -s $work/targets.tsv ]]; then
    echo "  nothing to do"
    return 0
  fi

  if [[ -s $work/container.tsv ]]; then
    local ref cuuid store storeuuid names
    while IFS=$'\t' read -r ref cuuid store storeuuid names; do
      [[ -n $cuuid ]] || continue
      remote_destructive delete-container \
        "/usr/sbin/diskutil apfs deleteContainer $cuuid"
      echo "  (container $ref addressed by its UUID $cuuid)"
    done <"$work/container.tsv"
  fi

  local identifier type name uuid size reason recheck
  while IFS=$'\t' read -r identifier type name uuid size reason; do
    [[ -n $uuid ]] || continue
    is_protected_uuid "$uuid" &&
      die "refusing to erase $uuid: it is on the protected list"

    # Re-read the partition immediately before erasing it. Identifiers move as
    # space is released; the UUID must still name a non-protected partition.
    # deleteContainer also removes its physical store partition from the
    # partition map on current macOS, so a target that no longer exists is
    # already freed — verified by asking, never assumed.
    if [[ $confirm == "yes" ]]; then
      if ! remote exists "/usr/sbin/diskutil info $uuid >/dev/null 2>&1"; then
        echo "  already freed $reason (was $identifier; removed with its container)"
        continue
      fi
      recheck=$(remote recheck "/usr/sbin/diskutil info $uuid | /usr/bin/awk '/Volume Name:/ { line = \$0; sub(/^ *Volume Name: */, \"\", line); print line }'")
      if [[ -n $recheck && $recheck =~ $PROTECTED_NAME_PATTERN ]]; then
        die "$uuid now reports volume name '$recheck' — refusing to erase it"
      fi
    fi

    remote_destructive erase-volume \
      "/usr/sbin/diskutil eraseVolume free none $uuid"
    echo "  freed $reason (was $identifier, $name)"
  done <"$work/targets.tsv"
}

clean_macos_state() {
  heading "Clearing installer staging, state, and old copies"
  local state size path
  IFS=$'\t' read -r state size path <"$work/app-support.tsv"
  if [[ $state == "present" ]]; then
    remote_destructive clear-app-support \
      "rm -rf \"\$HOME/Library/Application Support/$APP_SUPPORT_ID\""
    echo "  cleared staging, scratch, state and handoff"
  else
    echo "  staging/state already absent"
  fi

  if [[ -s $work/old-apps.txt ]]; then
    while IFS= read -r path; do
      [[ -n $path ]] || continue
      case $path in
        */"$APP_BUNDLE_NAME"|*/Omarchy-MX-Mac-Installer-*.zip|*/__MACOSX) ;;
        *) die "refusing to remove an unexpected path: $path" ;;
      esac
      # The installer package installs the app root-owned in /Applications;
      # copies in the user's own folders stay a plain rm.
      if [[ $path == /Applications/* ]]; then
        remote_destructive remove-old-app "sudo -n rm -rf \"$path\""
      else
        remote_destructive remove-old-app "rm -rf \"$path\""
      fi
    done <"$work/old-apps.txt"
  else
    echo "  no old installer copies to remove"
  fi

  echo
  echo "  NOT done here (owner step, needs sudo, changes system state):"
  echo "    sudo launchctl bootout system/$APP_SUPPORT_ID.helper"
  echo "    sudo rm -f /Library/LaunchDaemons/$APP_SUPPORT_ID.helper.plist"
  echo "  A fresh notarized app re-registers its own helper on first launch;"
  echo "  only unregister by hand if a stale registration blocks the run."
}

# ---------------------------------------------------------------------------

main() {
  while (( $# > 0 )); do
    case $1 in
      --confirm) confirm="yes"; shift ;;
      --dry-run) dry_run="yes"; shift ;;
      --host) host=${2:-}; shift 2 ;;
      --skip-partitions) skip_partitions="yes"; shift ;;
      --skip-macos-cleanup) skip_macos="yes"; shift ;;
      -h|--help) usage ;;
      *) echo "preclean-m1: unknown argument: $1" >&2; usage ;;
    esac
  done

  [[ -n $host ]] || die "--host must not be empty"
  if [[ $dry_run == "yes" && $confirm == "yes" ]]; then
    die "--dry-run and --confirm are mutually exclusive"
  fi
  if [[ $skip_partitions == "yes" && $skip_macos == "yes" ]]; then
    die "--skip-partitions and --skip-macos-cleanup together leave nothing to do"
  fi

  work=$(mktemp -d "${TMPDIR:-/private/tmp}/omarchy-preclean.XXXXXX") ||
    die "cannot create a working directory"
  chmod 0700 "$work"
  trap cleanup EXIT

  heading "Preflight"
  if [[ -n ${OMARCHY_PRECLEAN_SSH_SHIM:-} ]]; then
    note "SHIM MODE: using $OMARCHY_PRECLEAN_SSH_SHIM instead of ssh"
  fi
  verify_local_route
  verify_identity

  heading "Discovery (read-only)"
  read_partitions
  read_containers
  identify_protected
  if [[ $skip_partitions == "yes" ]]; then
    : >"$work/targets.tsv"
    : >"$work/container.tsv"
    note "partition work skipped (--skip-partitions)"
  else
    identify_omarchy
  fi
  if [[ $skip_macos == "yes" ]]; then
    printf 'absent\t0\t(skipped)\n' >"$work/app-support.tsv"
    : >"$work/old-apps.txt"
  else
    read_macos_cleanup_candidates
  fi

  print_plan

  if [[ $confirm != "yes" ]]; then
    heading "DRY RUN — nothing was changed"
    echo "  Re-run with --confirm to perform the plan above."
    echo "  Commands that would run:"
    if [[ $skip_partitions != "yes" ]]; then
      erase_partitions
    fi
    if [[ $skip_macos != "yes" ]]; then
      clean_macos_state
    fi
    echo
    echo "result=dry-run"
    echo "targets=$(grep -c '' "$work/targets.tsv" 2>/dev/null)"
    exit 0
  fi

  heading "CONFIRMED — performing the plan"
  if [[ $skip_partitions != "yes" ]]; then
    erase_partitions
  fi
  if [[ $skip_macos != "yes" ]]; then
    clean_macos_state
  fi

  heading "What was done"
  echo "  host=$host"
  echo "  destructive_commands_run=$actions_taken"
  echo "  partitions_freed=$(grep -c '' "$work/targets.tsv" 2>/dev/null)"
  echo "  protected_untouched=$(grep -c '' "$work/protected.txt" 2>/dev/null)"
  echo
  echo "  Verify with:"
  echo "    ssh $host '/usr/sbin/diskutil list /dev/disk0'"
  echo "    ssh $host '/usr/sbin/diskutil apfs list'"
  echo "  macOS and Recovery must still be present with the same partition UUIDs"
  echo "  listed under \"Protected\" above."
  echo
  echo "result=performed"
}

main "$@"
