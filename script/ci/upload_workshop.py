"""Upload the approved pack to the existing Workshop item using SteamCMD."""

import argparse
import base64
import hashlib
import json
import os
import re
import shutil
import subprocess
from pathlib import Path

from prepare_release import ROOT, VERSION

PACK_NAME = "tww3_mod_capacity_cost_control.pack"


def prepare_upload(pack: Path, expected_sha256: str, directory: Path) -> Path:
    metadata = json.loads((ROOT / "data/project.json").read_text(encoding="utf-8"))
    if not re.fullmatch(r"[1-9][0-9]*", metadata["workshop_id"]):
        raise ValueError("Refusing to create a new Workshop item")
    if not re.fullmatch(VERSION, metadata["version"]):
        raise ValueError("Invalid project version")
    if not re.fullmatch(r"[0-9a-f]{64}", expected_sha256):
        raise ValueError("Invalid expected pack SHA256")
    with pack.open("rb") as stream:
        if hashlib.file_digest(stream, "sha256").hexdigest() != expected_sha256:
            raise ValueError("Pack SHA256 differs from the approved build")
    content = directory / "content"
    content.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(pack, content / PACK_NAME)
    # 只更新内容和变更说明，保留工坊现有的标题、描述、封面及可见性。
    values = {
        "appid": "1142710",
        "publishedfileid": metadata["workshop_id"],
        "contentfolder": str(content.resolve()),
        "changenote": "v" + metadata["version"],
    }
    vdf = directory / "workshop.vdf"
    vdf.write_text('"workshopitem"\n{\n' + "".join(
        f"    {json.dumps(key)} {json.dumps(value)}\n" for key, value in values.items()
    ) + "}\n", encoding="utf-8")
    return vdf


def upload(steamcmd: Path, pack: Path, expected_sha256: str) -> None:
    username = os.environ["STEAM_USERNAME"]
    cached_config = base64.b64decode(os.environ["STEAM_CONFIG_VDF"], validate=True)
    if not username or not cached_config:
        raise ValueError("Steam username and authenticated config.vdf are required")
    vdf = prepare_upload(pack, expected_sha256, ROOT / "build/workshop")
    config = steamcmd.parent / "config/config.vdf"
    config.parent.mkdir(parents=True, exist_ok=True)
    config.write_bytes(cached_config)
    config.chmod(0o600)
    try:
        result = subprocess.run([
            str(steamcmd), "+@ShutdownOnFailedCommand", "1", "+@NoPromptForPassword", "1",
            "+login", username, "+workshop_build_item", str(vdf), "+quit",
        ], cwd=steamcmd.parent, stdin=subprocess.DEVNULL, capture_output=True, text=True)
        workshop_id = json.loads((ROOT / "data/project.json").read_text(encoding="utf-8"))["workshop_id"]
        # SteamCMD 某些失败也返回 0，必须确认本次上传的目标和成功消息。
        if result.returncode != 0 or not re.search(r"Success\. Uploaded item " + workshop_id + r"\b", result.stdout):
            output = (result.stdout + result.stderr).replace(username, "<Steam user>")
            raise RuntimeError(f"SteamCMD did not confirm the Workshop upload (exit {result.returncode}):\n{output}")
        print(f"Updated Workshop item {workshop_id}; pack SHA256: {expected_sha256}")
    finally:
        config.unlink(missing_ok=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--steamcmd", type=Path, required=True)
    parser.add_argument("--pack", type=Path, required=True)
    parser.add_argument("--sha256", required=True)
    args = parser.parse_args()
    upload(args.steamcmd.resolve(), args.pack.resolve(), args.sha256)
