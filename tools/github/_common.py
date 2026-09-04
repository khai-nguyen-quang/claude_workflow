#!/usr/bin/env python3
"""Shared utilities for GitHub Python tools.

Mirrors tools/gitlab/_common.py so the two tool directories are drop-in
interchangeable behind $WF_TOOLS.  The GitLab vocabulary is kept on purpose:
a ref of kind "mr" is a GitHub pull request.
"""

from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

GITHUB_API = "https://api.github.com"
GITHUB_WEB = "https://github.com"
API_VERSION = "2022-11-28"


def load_env() -> dict[str, str]:
    """Load key=value pairs from the .env file (three levels up from tools/github/)."""
    env_file = Path(__file__).resolve().parent.parent.parent / ".env"
    if not env_file.exists():
        print(f"Error: .env not found at {env_file}", file=sys.stderr)
        sys.exit(1)

    env: dict[str, str] = {}
    for raw in env_file.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        env[key.strip()] = value.strip().strip('"').strip("'")
    return env


def get_token() -> str:
    """Return GH_TOKEN, preferring the .env file over the environment."""
    env = load_env()
    token = env.get("GH_TOKEN") or os.environ.get("GH_TOKEN", "")
    if not token:
        print("Error: GH_TOKEN not set in .env", file=sys.stderr)
        sys.exit(1)
    return token


def resolve_ref(ref: str) -> tuple[str, str, str, int]:
    """
    Parse a GitHub ref into (kind, owner, repo, number).

    kind: 'mr' (pull request) or 'issue'

    Accepted formats:
      Full URL     https://github.com/<owner>/<repo>/issues/12
                   https://github.com/<owner>/<repo>/pull/45
      Short PR     <owner>/<repo>#PR!45
      Short issue  <owner>/<repo>#12

    A GitHub ref always carries owner/repo: a bare ref such as "camera-daemon#12"
    belongs to GitLab (see tools/forge/resolve.sh).
    """
    m = re.match(r"https?://[^/]+/([^/]+)/([^/]+)/(issues|pull)/(\d+)", ref)
    if m:
        owner, repo, kind_raw, number = m.group(1), m.group(2), m.group(3), int(m.group(4))
        return ("mr" if kind_raw == "pull" else "issue"), owner, repo, number

    m = re.match(r"^([^/#]+)/([^/#]+)#PR!(\d+)$", ref)
    if m:
        return "mr", m.group(1), m.group(2), int(m.group(3))

    m = re.match(r"^([^/#]+)/([^/#]+)#(\d+)$", ref)
    if m:
        return "issue", m.group(1), m.group(2), int(m.group(3))

    print(f"Error: cannot parse GitHub ref '{ref}'", file=sys.stderr)
    print("  Accepted formats:", file=sys.stderr)
    print(f"    Full URL:    {GITHUB_WEB}/<owner>/<repo>/issues/<n>", file=sys.stderr)
    print("    Short PR:    <owner>/<repo>#PR!45", file=sys.stderr)
    print("    Short issue: <owner>/<repo>#12", file=sys.stderr)
    sys.exit(1)


def _request(method: str, endpoint: str, token: str, payload: dict | None = None,
             params: dict | None = None) -> tuple[dict | list, dict]:
    """Authenticated request to the GitHub REST API. Returns (parsed JSON, headers)."""
    url = f"{GITHUB_API}{endpoint}"
    if params:
        url += "?" + urllib.parse.urlencode(params)

    data = json.dumps(payload).encode() if payload is not None else None
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": API_VERSION,
        "User-Agent": "claude-workflow",
    }
    if data is not None:
        headers["Content-Type"] = "application/json"

    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as resp:
            body = resp.read().decode()
            parsed = json.loads(body) if body.strip() else {}
            return parsed, dict(resp.headers)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode(errors="replace")
        print(f"Error: GitHub API {exc.code} for {method} {url}", file=sys.stderr)
        print(f"  {body}", file=sys.stderr)
        if exc.code == 404:
            print("  A 404 on a repo you can see over SSH usually means the token's", file=sys.stderr)
            print("  repository access does not include it (fine-grained PATs list repos", file=sys.stderr)
            print("  explicitly). Check Settings > Developer settings > Personal access", file=sys.stderr)
            print("  tokens > Repository access.", file=sys.stderr)
        sys.exit(1)
    except urllib.error.URLError as exc:
        print(f"Error: cannot reach {url}: {exc.reason}", file=sys.stderr)
        sys.exit(1)


def api_get(endpoint: str, token: str, params: dict | None = None) -> dict | list:
    return _request("GET", endpoint, token, params=params)[0]


def api_post(endpoint: str, token: str, payload: dict) -> dict:
    return _request("POST", endpoint, token, payload=payload)[0]


def api_patch(endpoint: str, token: str, payload: dict) -> dict:
    return _request("PATCH", endpoint, token, payload=payload)[0]


def api_get_paged(endpoint: str, token: str, params: dict | None = None) -> list:
    """Fetch every page of a paginated endpoint, following the Link header.

    GitHub signals the last page by omitting rel="next" -- a short page is NOT a
    reliable terminator the way it is on GitLab, so this follows Link instead.
    """
    results: list = []
    base_params = dict(params or {})
    base_params["per_page"] = 100
    page = 1

    while True:
        base_params["page"] = page
        data, headers = _request("GET", endpoint, token, params=base_params)
        if not isinstance(data, list):
            return results
        results.extend(data)
        if 'rel="next"' not in headers.get("Link", ""):
            break
        page += 1

    return results


def api_exists(endpoint: str, token: str) -> bool:
    """True if the endpoint returns 2xx, False on 404. Any other error is fatal.

    Separate from api_get because a 404 is a legitimate answer for existence
    checks (does this branch exist on the remote?) rather than a failure.
    """
    req = urllib.request.Request(
        f"{GITHUB_API}{endpoint}",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": API_VERSION,
            "User-Agent": "claude-workflow",
        },
    )
    try:
        urllib.request.urlopen(req)
        return True
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            return False
        print(f"Error: GitHub API {exc.code} for GET {endpoint}", file=sys.stderr)
        print(f"  {exc.read().decode(errors='replace')}", file=sys.stderr)
        sys.exit(1)
    except urllib.error.URLError as exc:
        print(f"Error: cannot reach GitHub: {exc.reason}", file=sys.stderr)
        sys.exit(1)


def graphql(query: str, token: str, variables: dict | None = None) -> dict:
    """Call the GraphQL API. Needed for operations REST does not expose,
    notably resolving a pull request review thread."""
    payload = {"query": query, "variables": variables or {}}
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        f"{GITHUB_API}/graphql",
        data=data,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "User-Agent": "claude-workflow",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req) as resp:
            result = json.loads(resp.read().decode())
    except urllib.error.HTTPError as exc:
        print(f"Error: GitHub GraphQL {exc.code}", file=sys.stderr)
        print(f"  {exc.read().decode(errors='replace')}", file=sys.stderr)
        sys.exit(1)
    except urllib.error.URLError as exc:
        print(f"Error: cannot reach the GraphQL API: {exc.reason}", file=sys.stderr)
        sys.exit(1)

    if result.get("errors"):
        print("Error: GraphQL returned errors", file=sys.stderr)
        for err in result["errors"]:
            print(f"  {err.get('message')}", file=sys.stderr)
        sys.exit(1)
    return result.get("data") or {}
