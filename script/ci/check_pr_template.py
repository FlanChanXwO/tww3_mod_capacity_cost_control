"""Check PR descriptions without executing contributor-provided content."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

SECTIONS = ("变更点 / Changes", "验证步骤 / Verification", "检查清单 / Checklist")
CHECKS = (
    "没有引入恶意代码 / No malicious code",
    "涉及的行为、配置或兼容影响已说明 / Relevant behavior, configuration, or compatibility impacts are documented",
)


def validate(body: str | None) -> list[str]:
    text = re.sub(r"<!--.*?(?:-->|$)", "", body or "", flags=re.DOTALL)
    sections: dict[str, list[str]] = {}
    checked = set()
    current = None
    fence = ""
    for line in text.splitlines():
        marker = re.match(r"^ {0,3}(`{3,}|~{3,})(.*)$", line)
        if fence:
            if marker and marker[1][0] == fence[0] and len(marker[1]) >= len(fence) and not marker[2].strip():
                fence = ""
            elif current:
                sections[current].append(line)
            continue
        if marker:
            fence = marker[1]
            continue
        heading = re.match(r"^ {0,3}##\s+(.+?)(?:\s+#+)?\s*$", line)
        if heading:
            current = heading[1] if heading[1] in SECTIONS else None
            if current:
                sections.setdefault(current, [])
            continue
        if current:
            sections[current].append(line)
            if current == SECTIONS[2]:
                item = re.fullmatch(r" {0,3}[-*+]\s+\[[xX]\]\s+(.+?)\s*", line)
                if item:
                    checked.add(item[1])

    errors = []
    for section in SECTIONS[:2]:
        content = "\n".join(sections.get(section, []))
        if not re.sub(r"[\s#>*_\-`~]", "", content):
            errors.append(f"请填写 / Please complete: {section}")
    for item in CHECKS:
        if item not in checked:
            errors.append(f"请确认并勾选 / Please confirm and check: {item}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--body-file", type=Path, help="PR 正文文件 / PR body file")
    source.add_argument("--event-file", type=Path, help="GitHub 事件文件 / GitHub event file")
    args = parser.parse_args()
    try:
        if args.event_file:
            event = json.loads(args.event_file.read_text(encoding="utf-8"))
            body = event["pull_request"]["body"]
        else:
            body = args.body_file.read_text(encoding="utf-8")
        if body is not None and not isinstance(body, str):
            raise ValueError("PR 正文必须是文本 / PR body must be text")
    except (OSError, UnicodeError, ValueError, KeyError, TypeError) as error:
        print(f"错误 / Error: {error}", file=sys.stderr)
        return 1

    errors = validate(body)
    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        return 1
    print("PR 模板检查通过 / PR template check passed")
    return 0


if __name__ == "__main__":
    # Windows 控制台编码不影响双语检查结果。
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    raise SystemExit(main())
