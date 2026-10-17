"""Apply Issue type labels and assign unowned Issues to the project author."""

import argparse
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def triage_issue(number: int, author: str) -> None:
    if type(number) is not int or number <= 0 or not author:
        raise ValueError("Invalid Issue number or project author")
    # 事件快照可能已过期；读取当前状态，保留后来添加的标签和指派。
    result = subprocess.run([
        "gh", "issue", "view", str(number), "--json", "title,labels,assignees",
    ], check=True, capture_output=True, text=True, encoding="utf-8")
    issue = json.loads(result.stdout)
    labels = {label["name"] for label in issue["labels"]}
    command = ["gh", "issue", "edit", str(number)]
    for prefix, label in (("[Bug]", "bug"), ("[Feature]", "enhancement")):
        if issue["title"].startswith(prefix):
            if label not in labels:
                command.extend(["--add-label", label])
            break
    if not issue["assignees"]:
        command.extend(["--add-assignee", author])
    if len(command) > 4:
        subprocess.run(command, check=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--event-file", type=Path, required=True)
    args = parser.parse_args()
    event = json.loads(args.event_file.read_text(encoding="utf-8"))
    project = json.loads((ROOT / "data" / "project.json").read_text(encoding="utf-8"))
    triage_issue(event["issue"]["number"], project["author"])


if __name__ == "__main__":
    main()
