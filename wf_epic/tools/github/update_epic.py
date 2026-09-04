#!/usr/bin/env python3
"""
Update the body of a GitHub issue acting as an epic.

The new body is read from a file, never from an argument: a description is
multi-line Markdown and shell quoting mangles it silently.

Usage:
    update_epic.py owner/repo#1 --description-file <path>
    update_epic.py owner/repo#1 --description-file <path> --dry-run
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent.parent / "tools" / "github"))
from _common import api_patch, get_token  # noqa: E402

from fetch_epic import parse_ref  # noqa: E402


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("ref", help="owner/repo#<n>")
    ap.add_argument("--description-file", required=True, type=Path)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    owner, repo, number = parse_ref(a.ref)
    body = a.description_file.read_text()

    if a.dry_run:
        lines = body.splitlines()
        print(f"DRY RUN — would set the body of {owner}/{repo}#{number} to "
              f"{len(lines)} line(s), {len(body)} chars:")
        for line in lines[:10]:
            print(f"  {line}")
        if len(lines) > 10:
            print(f"  … (+{len(lines) - 10} lines)")
        return

    issue = api_patch(f"/repos/{owner}/{repo}/issues/{number}", get_token(), {"body": body})
    print(f"updated {owner}/{repo}#{issue['number']}  {issue['html_url']}")


if __name__ == "__main__":
    main()
