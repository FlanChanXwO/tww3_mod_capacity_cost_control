"""Assign unowned PRs and request the maintainer's review when eligible."""

import argparse
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def triage_pr(number: int, maintainer: str) -> None:
    if type(number) is not int or number <= 0 or not maintainer:
        raise ValueError("Invalid PR number or maintainer")
    result = subprocess.run([
        "gh", "pr", "view", str(number), "--json", "author,assignees,reviewRequests,isDraft,reviews",
    ], check=True, capture_output=True, text=True, encoding="utf-8")
    pr = json.loads(result.stdout)
    command = ["gh", "pr", "edit", str(number)]
    if not pr["assignees"]:
        command.extend(["--add-assignee", maintainer])
    # GitHub 禁止作者审查自己；已有审查或指派时保留人工选择。
    reviewed = any(review["author"]["login"] == maintainer for review in pr["reviews"])
    if pr["author"]["login"] != maintainer and not pr["isDraft"] and not pr["reviewRequests"] and not reviewed:
        command.extend(["--add-reviewer", maintainer])
    if len(command) > 4:
        subprocess.run(command, check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--event-file", type=Path, required=True)
    args = parser.parse_args()
    event = json.loads(args.event_file.read_text(encoding="utf-8"))
    project = json.loads((ROOT / "data/project.json").read_text(encoding="utf-8"))
    triage_pr(event["pull_request"]["number"], project["author"])
