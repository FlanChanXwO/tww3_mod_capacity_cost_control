"""Record a Workshop release using an existing GitHub version tag."""

import argparse
import re
import subprocess
import tempfile
from pathlib import Path


def record_release(tag: str, workshop_id: str, pack_sha256: str) -> None:
    for name, value, pattern in (
        ("tag", tag, r"v[0-9]+\.[0-9]+\.[0-9]+"),
        ("workshop_id", workshop_id, r"[0-9]+"),
        ("pack_sha256", pack_sha256, r"[0-9a-fA-F]{64}"),
    ):
        if not re.fullmatch(pattern, value):
            raise ValueError(f"Invalid {name}: {value!r}")
    notes = (
        f"Workshop: https://steamcommunity.com/sharedfiles/filedetails/?id={workshop_id}\n"
        f"Pack SHA256: {pack_sha256}\n"
    )
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "release-notes.md"
        path.write_text(notes, encoding="utf-8")
        # 未验收或不存在的 tag 不应由登记流程自动创建。
        subprocess.run([
            "gh", "release", "create", tag, "--verify-tag", "--title", tag,
            "--notes-file", str(path),
        ], check=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--workshop-id", required=True)
    parser.add_argument("--pack-sha256", required=True)
    args = parser.parse_args()
    record_release(args.tag, args.workshop_id, args.pack_sha256)


if __name__ == "__main__":
    main()
