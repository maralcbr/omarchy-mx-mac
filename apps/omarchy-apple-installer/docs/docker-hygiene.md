# Docker Desktop pins deleted files — restart it between build marathons

## The problem

Docker Desktop runs a Linux VM that reaches into the Mac's filesystem through
virtiofs. When a build inside the VM opens host files, the VM holds file
handles open. Those handles survive the container that made them.

If the host then deletes those files, the disk space is **not** returned. The
files are unlinked from the directory tree but still held open by
`com.docker.virtualization`, so macOS keeps the blocks allocated. `du` and
Finder both report the space as free. It is not.

Observed on 2026-08-31: roughly **12,000 open handles holding about 330 GB**
after a run of OS payload builds and a reviewed cleanup. The cleanup looked
like it worked; the disk did not grow back.

## How to detect it

```bash
lsof +L1 2>/dev/null | grep -i -E 'docker|virtualization'
```

`+L1` lists open files whose link count is below 1 — that is, files already
deleted but still open. Any lines belonging to Docker are space that a restart
will return.

Note that `lsof` truncates the COMMAND column to nine characters, so
`com.docker.virtualization` appears as `com.docke` — match on the whole line,
not on the process name alone.

To see how much (column 7 is SIZE/OFF once `+L1` inserts the NLINK column):

```bash
lsof +L1 2>/dev/null |
  awk 'tolower($0) ~ /docker|virtualization/ && $7 ~ /^[0-9]+$/ {
         bytes += $7; n += 1
       }
       END { printf "%d handles, %.1f GB pinned\n", n, bytes / 1073741824 }'
```

Add `sudo` if Docker Desktop is running under a different account than the one
you are logged in as; without it `lsof` only reports your own processes.

Cross-check against what the volume claims:

```bash
df -h /System/Volumes/Data
```

A large gap between "free space" here and what you expected after a cleanup is
the same symptom seen from the other side.

## The fix

Quit and reopen Docker Desktop. The VM shuts down, every handle is released,
and the space comes back immediately. Nothing else is needed — no reboot, no
`docker system prune`, no unmounting.

```bash
osascript -e 'quit app "Docker"'
sleep 20
open -a Docker
```

`docker system prune` does **not** fix this. It reclaims Docker's own images
and layers inside the VM; this is host-side space held by the VM process.

## When to do it

- After any run of image or payload builds.
- After deleting build artifacts or running a store cleanup, and **before**
  measuring how much space you got back — otherwise the measurement is wrong.
- Before starting a long build, so it begins with the full disk available.

Treat "restart Docker Desktop" as a normal step between build marathons, not
as troubleshooting.
