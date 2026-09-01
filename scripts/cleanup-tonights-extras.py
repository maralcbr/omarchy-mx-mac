#!/usr/bin/env python3
"""Reviewed cleanup of tonight's superseded build checkpoints.

Authorized by the owner ("A", 2026-08-30). Policy:
- Never touches anything completed before 2026-08-30 (the legacy store).
- Keeps, per stage and per build mode, the newest generation from today.
- Deletes only today's superseded checkpoint directories, plus objects that
  are referenced by deleted checkpoints and by NOTHING kept (reference walk
  over every remaining manifest in the whole store), and that were created
  today.
- `plan` writes cleanup-manifest.json beside this script and prints a
  summary. `apply` re-scans, refuses on any drift from the manifest, then
  deletes exactly the listed paths and re-verifies every keeper.
Evidence directories, release/, mirrors, node cache, rollback checkpoints
and /private/tmp candidates are never in scope.
"""

import datetime
import json
import os
import shutil
import stat
import sys
from pathlib import Path

STORE = Path(os.path.expanduser("~/.cache/omarchy/asahi-checkpoints"))
TODAY = datetime.date(2026, 8, 31)
MANIFEST = Path(__file__).with_name("cleanup-manifest.json")


def scan():
    keep, delete, errors = [], [], []
    for stage_dir in sorted((STORE / "checkpoints").iterdir()):
        if stage_dir.name.startswith("."):
            errors.append(f"blocked entry left alone: {stage_dir.name}")
            continue
        if not stage_dir.is_dir() or stage_dir.is_symlink():
            errors.append(f"unexpected entry left alone: {stage_dir}")
            continue
        rows = []
        for ident in sorted(stage_dir.iterdir()):
            if not ident.is_dir() or ident.is_symlink():
                errors.append(f"unexpected entry left alone: {ident}")
                continue
            try:
                man = json.loads((ident / "manifest.json").read_text())
            except Exception as exc:
                errors.append(f"unreadable manifest kept safe: {ident}: {exc}")
                continue
            day = datetime.date.fromtimestamp(ident.stat().st_mtime)
            rows.append(
                {
                    "stage": stage_dir.name,
                    "identity": ident.name,
                    "mode": man.get("mode"),
                    "completed_at": man.get("completed_at", ""),
                    "day": day,
                    "path": ident,
                    "outputs": [
                        o["sha256"]
                        for o in man.get("outputs", [])
                        if o.get("kind") == "file"
                    ],
                }
            )
        todays = [r for r in rows if r["day"] >= TODAY]
        keep.extend(r for r in rows if r["day"] < TODAY)
        newest = {}
        for r in todays:
            k = r["mode"]
            if k not in newest or r["completed_at"] > newest[k]["completed_at"]:
                newest[k] = r
        for r in todays:
            (keep if r is newest.get(r["mode"]) else delete).append(r)

    kept_refs = {sha for r in keep for sha in r["outputs"]}
    del_refs = {sha for r in delete for sha in r["outputs"]}
    orphans, reclaim = [], 0
    for sha in sorted(del_refs - kept_refs):
        op = STORE / "objects" / "sha256" / sha[:2] / sha
        if op.is_file() and not op.is_symlink():
            if datetime.date.fromtimestamp(op.stat().st_mtime) >= TODAY:
                reclaim += op.stat().st_blocks * 512
                orphans.append(str(op))
            else:
                errors.append(f"pre-existing orphan left alone: {sha[:16]}")
    for r in delete:
        for f in r["path"].rglob("*"):
            if f.is_file():
                reclaim += f.stat().st_blocks * 512
    return keep, delete, orphans, reclaim, errors


def plan():
    keep, delete, orphans, reclaim, errors = scan()
    doc = {
        "authorized_by": 'owner reply "A", 2026-08-30',
        "keep_count": len(keep),
        "delete_checkpoints": sorted(
            f'{r["stage"]}/{r["identity"]} mode={r["mode"]} completed={r["completed_at"]}'
            for r in delete
        ),
        "delete_checkpoint_paths": sorted(str(r["path"]) for r in delete),
        "orphan_objects": orphans,
        "estimated_reclaim_gb": round(reclaim / 2**30, 1),
        "errors": errors,
    }
    MANIFEST.write_text(json.dumps(doc, indent=2) + "\n")
    print(f"keep {len(keep)} checkpoints; delete {len(delete)} checkpoints "
          f"and {len(orphans)} orphaned objects")
    print(f"estimated reclaim: {doc['estimated_reclaim_gb']} GB")
    for line in doc["delete_checkpoints"]:
        print("  DEL", line)
    if errors:
        print("notes:")
        for e in errors:
            print("  ", e)
    print(f"manifest written: {MANIFEST}")


def apply():
    if not MANIFEST.is_file():
        sys.exit("no cleanup-manifest.json — run plan first")
    doc = json.loads(MANIFEST.read_text())
    keep, delete, orphans, _, _ = scan()
    fresh_paths = sorted(str(r["path"]) for r in delete)
    if fresh_paths != doc["delete_checkpoint_paths"] or orphans != doc["orphan_objects"]:
        sys.exit("store drifted since plan — re-run plan and review again")
    freed_before = shutil.disk_usage("/System/Volumes/Data").free
    for p in doc["delete_checkpoint_paths"]:
        path = Path(p)
        if not path.is_dir() or path.is_symlink() or STORE not in path.parents:
            sys.exit(f"refusing unexpected path: {p}")
        for node in [*path.rglob("*"), path]:
            os.chmod(node, stat.S_IMODE(node.lstat().st_mode) | stat.S_IWUSR)
        shutil.rmtree(path)
    for p in doc["orphan_objects"]:
        path = Path(p)
        if not path.is_file() or path.is_symlink() or STORE not in path.parents:
            sys.exit(f"refusing unexpected path: {p}")
        os.chmod(path, stat.S_IMODE(path.lstat().st_mode) | stat.S_IWUSR)
        path.unlink()
    missing = [str(r["path"]) for r in keep if not (r["path"] / "manifest.json").is_file()]
    if missing:
        sys.exit(f"POST-CHECK FAILURE — kept checkpoints missing: {missing[:3]}")
    freed = shutil.disk_usage("/System/Volumes/Data").free - freed_before
    print(f"done; kept {len(keep)} checkpoints verified; freed ~{freed / 2**30:.1f} GB")


LEGACY_MANIFEST = Path(__file__).with_name("cleanup-manifest-legacy.json")


def scan_legacy():
    """Owner-authorized second pass: delete every checkpoint completed before
    today (the pre-existing legacy store, proven unbound and rekey-ineligible),
    keep all of today's survivors, and remove objects referenced by nothing
    kept. Evidence directories are outside the store and untouched."""
    keep, delete, errors = [], [], []
    for stage_dir in sorted((STORE / "checkpoints").iterdir()):
        if stage_dir.name.startswith(".") or not stage_dir.is_dir() or stage_dir.is_symlink():
            errors.append(f"anomalous entry left alone: {stage_dir.name}")
            continue
        for ident in sorted(stage_dir.iterdir()):
            if not ident.is_dir() or ident.is_symlink():
                errors.append(f"anomalous entry left alone: {ident}")
                continue
            try:
                man = json.loads((ident / "manifest.json").read_text())
            except Exception as exc:
                errors.append(f"unreadable manifest kept safe: {ident}: {exc}")
                continue
            day = datetime.date.fromtimestamp(ident.stat().st_mtime)
            row = {
                "stage": stage_dir.name, "identity": ident.name,
                "mode": man.get("mode"), "completed_at": man.get("completed_at", ""),
                "path": ident,
                "outputs": [o["sha256"] for o in man.get("outputs", []) if o.get("kind") == "file"],
            }
            (keep if day >= TODAY else delete).append(row)
    kept_refs = {sha for r in keep for sha in r["outputs"]}
    del_refs = {sha for r in delete for sha in r["outputs"]}
    orphans, reclaim = [], 0
    for sha in sorted(del_refs - kept_refs):
        op = STORE / "objects" / "sha256" / sha[:2] / sha
        if op.is_file() and not op.is_symlink():
            reclaim += op.stat().st_blocks * 512
            orphans.append(str(op))
    for r in delete:
        for f in r["path"].rglob("*"):
            if f.is_file():
                reclaim += f.stat().st_blocks * 512
    return keep, delete, orphans, reclaim, errors


def plan_legacy():
    keep, delete, orphans, reclaim, errors = scan_legacy()
    doc = {
        "authorized_by": 'owner reply "clean legacy too", 2026-08-30',
        "keep_count": len(keep),
        "delete_checkpoints": sorted(
            f'{r["stage"]}/{r["identity"]} mode={r["mode"]} completed={r["completed_at"]}'
            for r in delete),
        "delete_checkpoint_paths": sorted(str(r["path"]) for r in delete),
        "orphan_objects": orphans,
        "estimated_reclaim_gb": round(reclaim / 2**30, 1),
        "errors": errors,
    }
    LEGACY_MANIFEST.write_text(json.dumps(doc, indent=2) + "\n")
    print(f"keep {len(keep)} (all of today's); delete {len(delete)} legacy checkpoints "
          f"and {len(orphans)} orphaned objects")
    print(f"estimated reclaim: {doc['estimated_reclaim_gb']} GB")
    by_stage = {}
    for r in delete:
        by_stage[r["stage"]] = by_stage.get(r["stage"], 0) + 1
    for s_, n in sorted(by_stage.items()):
        print(f"  {s_}: {n} legacy identities")
    for e in errors:
        print("  note:", e)
    print(f"manifest written: {LEGACY_MANIFEST}")


def apply_legacy():
    if not LEGACY_MANIFEST.is_file():
        sys.exit("no legacy manifest — run plan-legacy first")
    doc = json.loads(LEGACY_MANIFEST.read_text())
    keep, delete, orphans, _, _ = scan_legacy()
    if sorted(str(r["path"]) for r in delete) != doc["delete_checkpoint_paths"] \
            or orphans != doc["orphan_objects"]:
        sys.exit("store drifted since plan-legacy — re-run plan-legacy and review")
    for p_ in doc["delete_checkpoint_paths"]:
        path = Path(p_)
        if not path.is_dir() or path.is_symlink() or STORE not in path.parents:
            sys.exit(f"refusing unexpected path: {p_}")
        for node in [*path.rglob("*"), path]:
            os.chmod(node, stat.S_IMODE(node.lstat().st_mode) | stat.S_IWUSR)
        shutil.rmtree(path)
    for p_ in doc["orphan_objects"]:
        path = Path(p_)
        if not path.is_file() or path.is_symlink() or STORE not in path.parents:
            sys.exit(f"refusing unexpected path: {p_}")
        os.chmod(path, stat.S_IMODE(path.lstat().st_mode) | stat.S_IWUSR)
        path.unlink()
    missing = []
    for r in keep:
        if not (r["path"] / "manifest.json").is_file():
            missing.append(str(r["path"]))
        for sha in r["outputs"]:
            if not (STORE / "objects" / "sha256" / sha[:2] / sha).is_file():
                missing.append(f"object {sha[:16]}")
    if missing:
        sys.exit(f"POST-CHECK FAILURE: {missing[:5]}")
    print(f"done; all {len(keep)} kept checkpoints and every kept object verified present")


if __name__ == "__main__":
    {"plan": plan, "apply": apply,
     "plan-legacy": plan_legacy, "apply-legacy": apply_legacy}.get(
        sys.argv[1] if len(sys.argv) > 1 else "",
        lambda: sys.exit("usage: plan|apply|plan-legacy|apply-legacy"),
    )()
