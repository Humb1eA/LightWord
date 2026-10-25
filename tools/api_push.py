#!/usr/bin/env python3
"""Push the working tree to GitHub with the REST API.

Why this exists: on this machine `github.com:443` is blocked and the local proxy
is flaky, so `git push` fails. `api.github.com` is reachable, so we build blobs,
a tree, a commit and update the ref over HTTPS instead.

    python tools/api_push.py Humb1eA/LightWord "message"

Token: $GITHUB_TOKEN, or ~/.dsh/github_token.txt.

Notes
- A brand-new repo has no commits, and `git/blobs` answers 409 "Git Repository
  is empty.", so the first file goes in through the Contents API.
- Files under .github/workflows/ cannot be pushed with a token that lacks the
  `workflow` scope; this script refuses to even try and tells you.
"""
from __future__ import annotations

import base64
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
API = "https://api.github.com"
SKIP_DIRS = {".git", "build", "__pycache__", ".swiftpm", "DerivedData"}
SKIP_SUFFIXES = {".ipa"}

TOKEN = os.environ.get("GITHUB_TOKEN", "").strip()
if not TOKEN:
    token_file = Path(os.path.expanduser("~")) / ".dsh" / "github_token.txt"
    if token_file.exists():
        TOKEN = token_file.read_text(encoding="utf-8").strip()
if not TOKEN:
    raise SystemExit("no token: set GITHUB_TOKEN or ~/.dsh/github_token.txt")


class ApiError(Exception):
    def __init__(self, status: int, body: str):
        super().__init__(f"{status}: {body}")
        self.status = status
        self.body = body


def api(method: str, path: str, payload=None) -> dict:
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    request = urllib.request.Request(API + path, data=data, method=method)
    request.add_header("Authorization", f"Bearer {TOKEN}")
    request.add_header("Accept", "application/vnd.github+json")
    request.add_header("X-GitHub-Api-Version", "2022-11-28")
    request.add_header("User-Agent", "lightword-api-push")
    if data is not None:
        request.add_header("Content-Type", "application/json")

    try:
        with urllib.request.urlopen(request, timeout=90) as response:
            body = response.read()
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as error:
        raise ApiError(error.code, error.read().decode("utf-8", "replace"))


def collect_files() -> list[Path]:
    files: list[Path] = []
    for path in sorted(ROOT.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(ROOT)
        if any(part in SKIP_DIRS for part in relative.parts):
            continue
        if path.suffix in SKIP_SUFFIXES or path.name == ".DS_Store":
            continue
        files.append(path)
    return files


def relative(path: Path) -> str:
    return str(path.relative_to(ROOT)).replace("\\", "/")


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: python tools/api_push.py <owner/repo> [commit message]", file=sys.stderr)
        return 2

    repo = argv[1]
    message = argv[2] if len(argv) > 2 else "Sync working tree"
    files = collect_files()

    blocked = [relative(p) for p in files if relative(p).startswith(".github/workflows/")]
    if blocked:
        print("refusing to push workflow files (token needs `workflow` scope):")
        for name in blocked:
            print(f"  {name}")
        print("upload them through the web UI instead.")
        return 1

    print(f"repo: {repo}")
    print(f"files: {len(files)}")

    try:
        ref = api("GET", f"/repos/{repo}/git/ref/heads/main")
        parent = ref["object"]["sha"]
        print(f"existing head: {parent[:7]}")
    except ApiError as error:
        # An empty repository answers 409 "Git Repository is empty." (or 404 on
        # older deployments); both mean "no first commit yet".
        if error.status not in (404, 409):
            raise
        parent = None
        print("empty repository: seeding the first commit via Contents API")
        seed = ROOT / "README.md"
        if not seed.exists():
            seed = files[0]
        created = api(
            "PUT",
            f"/repos/{repo}/contents/{relative(seed)}",
            {
                "message": "Initial commit",
                "content": base64.b64encode(seed.read_bytes()).decode("ascii"),
                "branch": "main",
            },
        )
        parent = created["commit"]["sha"]
        print(f"seeded: {parent[:7]} ({relative(seed)})")

    tree = []
    for index, path in enumerate(files, start=1):
        blob = api(
            "POST",
            f"/repos/{repo}/git/blobs",
            {
                "content": base64.b64encode(path.read_bytes()).decode("ascii"),
                "encoding": "base64",
            },
        )
        tree.append({"path": relative(path), "mode": "100644", "type": "blob", "sha": blob["sha"]})
        if index % 10 == 0 or index == len(files):
            print(f"  blobs {index}/{len(files)}")

    new_tree = api("POST", f"/repos/{repo}/git/trees", {"tree": tree})
    commit = api(
        "POST",
        f"/repos/{repo}/git/commits",
        {"message": message, "tree": new_tree["sha"], "parents": [parent]},
    )

    try:
        api(
            "PATCH",
            f"/repos/{repo}/git/refs/heads/main",
            {"sha": commit["sha"], "force": False},
        )
    except ApiError:
        api(
            "POST",
            f"/repos/{repo}/git/refs",
            {"ref": "refs/heads/main", "sha": commit["sha"]},
        )

    print(f"pushed: {commit['sha'][:7]} on main")
    print(f"https://github.com/{repo}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
