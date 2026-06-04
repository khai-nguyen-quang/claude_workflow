#!/usr/bin/env python3
"""Shared utilities for GitLab Python tools."""

from __future__ import annotations

import json
import os
import re
import sys
import urllib.parse
import urllib.request
import urllib.error
from pathlib import Path

def load_env() -> dict[str, str]:
    """Load key=value pairs from the .env file (three levels up from tools/gitlab/)."""
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


def _load_optional_env() -> dict[str, str]:
    """Load .env quietly; return empty dict if the file is missing."""
    env_file = Path(__file__).resolve().parent.parent.parent / ".env"
    if not env_file.exists():
        return {}
    env: dict[str, str] = {}
    for raw in env_file.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        env[key.strip()] = value.strip().strip('"').strip("'")
    return env


def _init_config() -> tuple[str, str]:
    """Read GL_URL and GL_NAMESPACE from .env; both are required."""
    cfg = _load_optional_env()
    url = cfg.get("GL_URL", "").strip()
    namespace = cfg.get("GL_NAMESPACE", "").strip()
    if not url:
        print("Error: GL_URL not set in .env", file=sys.stderr)
        sys.exit(1)
    if not namespace:
        print("Error: GL_NAMESPACE not set in .env", file=sys.stderr)
        sys.exit(1)
    return url, namespace


GITLAB_URL, GITLAB_NAMESPACE = _init_config()


def get_token() -> str:
    """Return GL_TOKEN, preferring the .env file over the environment."""
    env = load_env()
    token = env.get("GL_TOKEN") or os.environ.get("GL_TOKEN", "")
    if not token:
        print("Error: GL_TOKEN not set in .env", file=sys.stderr)
        sys.exit(1)
    return token


def resolve_ref(ref: str) -> tuple[str, str, int]:
    """
    Parse a GitLab ref into (kind, project_path, iid).

    kind: 'mr' or 'issue'

    Accepted formats:
      Full URL    https://gitlab.company.com/<path>/-/merge_requests/<id>
      Short MR    projectX#MR!177
      Short issue projectX#300
    """
    # Full URL — matches any host so GL_URL in .env is respected
    m = re.match(
        r"https?://[^/]+/(.+?)/-/(merge_requests|issues|work_items)/(\d+)",
        ref,
    )
    if m:
        path, kind_raw, iid = m.group(1), m.group(2), int(m.group(3))
        kind = "mr" if kind_raw == "merge_requests" else "issue"
        return kind, path, iid

    # Short MR: project#MR!id
    m = re.match(r"^([^#]+)#MR!(\d+)$", ref)
    if m:
        return "mr", f"{GITLAB_NAMESPACE}/{m.group(1)}", int(m.group(2))

    # Short issue: project#id
    m = re.match(r"^([^#]+)#(\d+)$", ref)
    if m:
        return "issue", f"{GITLAB_NAMESPACE}/{m.group(1)}", int(m.group(2))

    print(f"Error: cannot parse ref '{ref}'", file=sys.stderr)
    print("  Accepted formats:", file=sys.stderr)
    print(f"    Full URL:    {GITLAB_URL}/<path>/-/merge_requests/<id>", file=sys.stderr)
    print("    Short MR:    projectX#MR!177", file=sys.stderr)
    print("    Short issue: projectX#300", file=sys.stderr)
    sys.exit(1)


def encode_project(project_path: str) -> str:
    """URL-encode a project path for use in API endpoints."""
    return urllib.parse.quote(project_path, safe="")


def api_get(endpoint: str, token: str, params: dict | None = None) -> dict | list:
    """Authenticated GET to the GitLab v4 API. Returns parsed JSON."""
    url = f"{GITLAB_URL}/api/v4{endpoint}"
    if params:
        url += "?" + urllib.parse.urlencode(params)

    req = urllib.request.Request(url, headers={"PRIVATE-TOKEN": token})
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as exc:
        body = exc.read().decode(errors="replace")
        print(f"Error: GitLab API {exc.code} for {url}", file=sys.stderr)
        print(f"  {body}", file=sys.stderr)
        sys.exit(1)
    except urllib.error.URLError as exc:
        print(f"Error: cannot reach {url}: {exc.reason}", file=sys.stderr)
        sys.exit(1)


def api_post(endpoint: str, token: str, payload: dict) -> dict:
    """Authenticated POST to the GitLab v4 API. Returns parsed JSON."""
    url = f"{GITLAB_URL}/api/v4{endpoint}"
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        url,
        data=data,
        headers={"PRIVATE-TOKEN": token, "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as exc:
        body = exc.read().decode(errors="replace")
        print(f"Error: GitLab API {exc.code} for POST {url}", file=sys.stderr)
        print(f"  {body}", file=sys.stderr)
        sys.exit(1)
    except urllib.error.URLError as exc:
        print(f"Error: cannot reach {url}: {exc.reason}", file=sys.stderr)
        sys.exit(1)


def api_get_paged(endpoint: str, token: str, params: dict | None = None) -> list:
    """Fetch all pages from a paginated GitLab endpoint."""
    results = []
    page = 1
    base_params = dict(params or {})
    base_params["per_page"] = 100

    while True:
        base_params["page"] = page
        page_data = api_get(endpoint, token, params=base_params)
        if not isinstance(page_data, list) or not page_data:
            break
        results.extend(page_data)
        if len(page_data) < 100:
            break
        page += 1

    return results
