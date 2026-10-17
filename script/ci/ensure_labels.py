"""Initialize repository labels from the trusted branch configuration."""

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def ensure_labels() -> None:
    labels = json.loads((ROOT / ".github" / "labels.json").read_text(encoding="utf-8"))
    for name, values in labels.items():
        subprocess.run([
            "gh", "label", "create", name, "--force",
            "--color", values["color"], "--description", values["description"],
        ], check=True)


if __name__ == "__main__":
    ensure_labels()
