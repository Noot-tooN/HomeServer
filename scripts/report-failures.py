#!/usr/bin/env python3
"""Keep diagnostics locally; publish only an explicit allowlist to GitHub."""
import argparse
import datetime as dt
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import urllib.error
import urllib.request

REPOSITORY = "Noot-tooN/HomeServer"
MACHINE = "homeserver"
PHASES = {"fetch", "evaluation", "build", "deployment", "service", "test"}


def commit_of(generation):
    value = ((generation.get("source") or {}).get("git") or {}).get("selected_commit_id", "")
    return value if re.fullmatch(r"[0-9a-f]{40}", value) else "unknown"


def event(phase, commit, detail):
    assert phase in PHASES
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        commit = "unknown"
    key = hashlib.sha256(json.dumps([MACHINE, phase, commit, detail]).encode()).hexdigest()
    return {"schema_version": 1, "id": key, "machine": MACHINE, "repository": REPOSITORY,
            "phase": phase, "commit": commit, "detail": detail,
            "observed_at": dt.datetime.now(dt.timezone.utc).isoformat()}


def failures(status):
    result = []
    generations = list((status.get("store") or {}).get("generations") or [])
    generation = (status.get("builder") or {}).get("generation")
    if generation:
        generations.append(generation)
    for generation in generations:
        for phase, field in [("evaluation", "eval_err"), ("build", "build_err")]:
            error = generation.get(field)
            # Superseding a generation is normal, not a failed update.
            if error and error != "context canceled":
                result.append(event(phase, commit_of(generation), error))
    deployments = list((status.get("store") or {}).get("deployments") or [])
    deployment = (status.get("deployer") or {}).get("deployment")
    if deployment:
        deployments.append(deployment)
    for deployment in deployments:
        if deployment.get("status") == "failed" or deployment.get("error_msg"):
            result.append(event("deployment", commit_of(deployment.get("generation") or {}),
                                deployment.get("error_msg") or "Deployment failed"))
    repository = (status.get("fetcher") or {}).get("git_repository_status") or {}
    if repository.get("error_msg"):
        result.append(event("fetch", "unknown", repository["error_msg"]))
    for remote in repository.get("remotes") or []:
        error = remote.get("fetch_error_msg") or (remote.get("main") or {}).get("error_msg")
        if error:
            # The previously fetched SHA is not necessarily the failing revision.
            result.append(event("fetch", "unknown", error))
    return {item["id"]: item for item in result}.values()


def public_issue(item):
    # Never interpolate error text, logs, URLs, commit messages, or status JSON.
    if item["phase"] not in PHASES or not re.fullmatch(r"[0-9a-f]{64}", item["id"]):
        raise ValueError("Invalid event")
    commit = item["commit"] if re.fullmatch(r"[0-9a-f]{40}", item["commit"]) else "unknown"
    metadata = {"schema_version": 1, "incident_id": item["id"], "machine": MACHINE,
                "repository": REPOSITORY, "phase": item["phase"], "commit": commit}
    marker = f'<!-- homeserver-incident:{item["id"]} -->'
    body = (marker + "\n\nAutomated failure report. Detailed diagnostics remain on HomeServer; "
            "this issue intentionally contains no error text or logs.\n\n```json\n" +
            json.dumps(metadata, indent=2) + "\n```\n\n" +
            f'Local diagnostics: `/var/lib/homeserver-reporting/events/{item["id"]}.json`.\n\n'
            "A future repair worker must authenticate to the server to retrieve diagnostics. "
            "An open issue is a historical failure record, not proof the failure is still active. "
            "Confirm the current deployment before acting.\n")
    return {"title": f'[HomeServer] {item["phase"]} failure ({commit[:12]})', "body": body}


def atomic_write(path, data):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(data, indent=2) + "\n")
    temporary.replace(path)


def request(token, path, payload=None):
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request("https://api.github.com" + path, data=data, headers={
        "Authorization": "Bearer " + token,
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "homeserver-failure-reporter",
        "Content-Type": "application/json",
    })
    with urllib.request.urlopen(req, timeout=15) as response:
        return json.load(response)


def deliver(item, token):
    payload = public_issue(item)
    marker = f'<!-- homeserver-incident:{item["id"]} -->'
    # Also deduplicate across a crash after POST but before the local receipt.
    page = 1
    while True:
        issues = request(token, f"/repos/{REPOSITORY}/issues?state=all&per_page=100&page={page}")
        for issue in issues:
            if (issue.get("body") or "").startswith(marker):
                return issue["number"]
        if len(issues) < 100:
            break
        page += 1
    issue = request(token, f"/repos/{REPOSITORY}/issues", payload)
    return issue["number"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--state-dir", default="/var/lib/homeserver-reporting")
    parser.add_argument("--token-file", default="/run/secrets/github-reporting-token")
    args = parser.parse_args()
    os.umask(0o077)
    directory = Path(args.state_dir) / "events"
    directory.mkdir(parents=True, exist_ok=True)
    with (Path(args.state_dir) / "reporter.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        process(args, directory)


def process(args, directory):
    status = {}
    if args.self_test:
        items = [event("test", "unknown", "Synthetic reporting verification v1")]
    else:
        try:
            completed = subprocess.run(["comin", "status", "--json"], capture_output=True,
                                       text=True, timeout=20, check=True)
            status = json.loads(completed.stdout)
            items = failures(status)
        except (subprocess.SubprocessError, OSError, ValueError):
            items = [event("service", "unknown", "Comin status unavailable; inspect comin.service")]
    for item in items:
        path = directory / (item["id"] + ".json")
        if not path.exists():
            item["status_snapshot"] = status
            try:
                logs = subprocess.run(["journalctl", "-u", "comin", "-n", "100", "--no-pager"],
                                      capture_output=True, text=True, timeout=5)
                item["local_logs"] = logs.stdout[-32000:]
            except (subprocess.SubprocessError, OSError):
                item["local_logs"] = "Logs unavailable; query journalctl -u comin separately."
            atomic_write(path, item)
    pending = []
    for path in sorted(directory.glob("*.json")):
        item = json.loads(path.read_text())
        if not item.get("issue_number"):
            pending.append((path, item))
    if not pending:
        return
    token_path = Path(args.token_file)
    if not token_path.exists():
        print("Failure reports queued locally; GitHub issue token is not installed.", file=sys.stderr)
        return
    token = token_path.read_text().strip()
    for path, item in pending[:10]:
        try:
            item["issue_number"] = deliver(item, token)
            atomic_write(path, item)
            print(f'Reported incident {item["id"]} as issue #{item["issue_number"]}')
        except urllib.error.HTTPError as exc:
            print(f"GitHub reporting failed (HTTP {exc.code}); event remains queued.", file=sys.stderr)
            return
        except (urllib.error.URLError, TimeoutError, OSError):
            print("GitHub reporting unavailable; event remains queued.", file=sys.stderr)
            return


if __name__ == "__main__":
    main()
