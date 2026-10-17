"""Set the release version before validation and pack generation."""

import argparse
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VERSION = r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"


def prepare_release(version: str, resume: bool = False) -> str:
    if not re.fullmatch(VERSION, version):
        raise ValueError("Version must be MAJOR.MINOR.PATCH without a v prefix")
    path = ROOT / "data/project.json"
    metadata = json.loads(path.read_text(encoding="utf-8"))
    if tuple(map(int, version.split("."))) < tuple(map(int, metadata["version"].split("."))):
        raise ValueError("Release version cannot be older than the project version")
    if not re.fullmatch(r"[1-9][0-9]*", metadata["workshop_id"]):
        raise ValueError("A published Workshop item ID is required")
    tag = "v" + version
    existing = subprocess.run(["git", "show-ref", "--verify", "--quiet", "refs/tags/" + tag], cwd=ROOT)
    if existing.returncode == 0 and not resume:
        raise ValueError(f"Tag already exists: {tag}")
    if existing.returncode not in (0, 1):
        existing.check_returncode()
    metadata["version"] = version
    path.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if existing.returncode == 0:
        # 发布中途失败可重跑，但同一 tag 只能对应完全相同的源码。
        subprocess.run(["git", "diff", "--exit-code", tag, "--", "."], cwd=ROOT, check=True)
    return tag


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    parser.add_argument("--resume", action="store_true", help="Reuse a tag only when its source is identical")
    args = parser.parse_args()
    print(prepare_release(args.version, args.resume))
