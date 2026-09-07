#!/usr/bin/env python3
"""
Update a GitLab issue's description (and optionally its title).

OUTWARD-FACING. The split phase runs one of these at a time, showing the human what
changes before each one.

The previous description is printed before the write and, with --backup-dir, saved to
<dir>/<project>-<iid>_description.before.md — a GitLab issue keeps no description
history a human can easily recover, so the backup is the undo.

Usage:
    update_issue.py openpilot#391 --description-file body.md --dry-run
    update_issue.py openpilot#391 --description-file body.md --backup-dir .tmp/epic-91
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "tools" / "gitlab"))
from _common import (api_get, api_put, encode_project,  # noqa: E402
                     get_token, resolve_ref)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("ref", help="issue ref, e.g. openpilot#391")
    ap.add_argument("--title")
    ap.add_argument("--description-file", metavar="PATH")
    ap.add_argument("--backup-dir", metavar="DIR",
                    help="write the pre-update description here before writing")
    ap.add_argument("--dry-run", action="store_true", help="print the diff, write nothing")
    a = ap.parse_args()

    kind, project, iid = resolve_ref(a.ref)
    if kind != "issue":
        print(f"Error: {a.ref} is not an issue ref", file=sys.stderr)
        sys.exit(1)
    if not a.title and not a.description_file:
        print("Error: nothing to update — pass --title and/or --description-file",
              file=sys.stderr)
        sys.exit(1)

    token = get_token()
    endpoint = f"/projects/{encode_project(project)}/issues/{iid}"
    current = api_get(endpoint, token)

    payload: dict[str, str] = {}
    if a.title:
        payload["title"] = a.title
    if a.description_file:
        payload["description"] = Path(a.description_file).read_text()

    print(f"{a.ref} — {current['title']}")
    print(f"  {current['web_url']}")
    if a.title:
        print(f"  title  : {current['title']!r} -> {a.title!r}")
    if a.description_file:
        old = (current.get("description") or "").strip()
        new = payload["description"].strip()
        print(f"  body   : {len(old.splitlines())} lines -> {len(new.splitlines())} lines")
        if old == new:
            print("  (identical — nothing to write)")
            return

    if a.dry_run:
        print("DRY RUN — nothing written")
        return

    if a.backup_dir:
        out = Path(a.backup_dir) / f"{project.split('/')[-1]}-{iid}_description.before.md"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(current.get("description") or "")
        print(f"  backup : {out}")

    api_put(endpoint, token, payload)
    check = api_get(endpoint, token)
    if a.description_file and (check.get("description") or "").strip() != \
            payload["description"].strip():
        print(f"WARNING: {a.ref} description read back different from what was sent",
              file=sys.stderr)
        sys.exit(1)
    print(f"updated {a.ref}")


if __name__ == "__main__":
    main()
