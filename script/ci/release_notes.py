"""Extract a version's bilingual changelog entry without rewriting its contents."""

import argparse
import re
from pathlib import Path


def release_notes(changelog: Path, version: str) -> str:
    entries = re.split(r"(?=^## )", changelog.read_text(encoding="utf-8"), flags=re.MULTILINE)
    heading = r"^## \[" + re.escape(version) + r"\] - \d{4}-\d{2}-\d{2}\n"
    matches = [entry for entry in entries if re.match(heading, entry)]
    if len(matches) != 1:
        raise ValueError(f"Expected exactly one changelog entry for {version}")
    entry = matches[0].rstrip() + "\n"
    languages = re.search(r"^### 简体中文\n(.+?)^### English\n(.+)", entry, re.MULTILINE | re.DOTALL)
    if not languages or not all(re.search(r"(?m)^- \S", section) for section in languages.groups()):
        raise ValueError("Release notes require nonempty Simplified Chinese and English sections")
    return entry


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    parser.add_argument("--changelog", type=Path, default=Path(__file__).resolve().parents[2] / "CHANGELOG.md")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(release_notes(args.changelog, args.version), encoding="utf-8", newline="\n")
