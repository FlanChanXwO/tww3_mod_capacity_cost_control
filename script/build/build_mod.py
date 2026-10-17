"""Build the WH3 mod pack through RPFM's MCP server."""

from __future__ import annotations

import csv
import json
import shutil
from pathlib import Path

from rpfm_mcp import RpfmMcpClient

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "src"
DATA = ROOT / "data" / "rituals.json"
PROJECT = ROOT / "data" / "project.json"
CACHE = ROOT / "build" / "generated"
DIST = ROOT / "build"
PACK_NAME = "tww3_mod_capacity_cost_control.pack"
GENERATED_LUA_PATHS = {
    "generated_data.lua": "shared/generated_data.lua",
    "metadata.lua": "config/metadata.lua",
    "i18.lua": "shared/i18.lua",
}


def load_metadata() -> dict:
    return json.loads(DATA.read_text(encoding="utf-8"))


def load_project_metadata() -> dict:
    return json.loads(PROJECT.read_text(encoding="utf-8"))


def lua_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def generate_lua(metadata: dict) -> Path:
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / "generated_data.lua"
    lines = [
        "-- 仪式数据模块，由 script/build/build_mod.py 根据 data/rituals.json 生成。",
        "-- 提供各派系的仪式、效果标识、基础费用与原版递增参数。",
        "-- 仅返回数据；修改 JSON 真源后重新构建，不直接编辑此文件。",
        "local data = {}", "",
    ]

    for faction_id, faction in metadata.items():
        lines.append(f"data.{faction_id} = {{")
        lines.append(f"    id = {lua_string(faction_id)},")
        for key in ("faction_key", "culture_key", "cost_model"):
            if key in faction:
                lines.append(f"    {key} = {lua_string(faction[key])},")
        lines.append(f"    bundle_key = {lua_string(faction['bundle_key'])},")
        lines.append("    rituals = {")
        for ritual_key, effect_key, vanilla_rate, max_increases, base_cost in faction["rituals"]:
            lines.extend(
                [
                    "        {",
                    f"            key = {lua_string(ritual_key)},",
                    f"            effect_key = {lua_string(effect_key)},",
                    f"            vanilla_rate = {vanilla_rate},",
                    f"            max_increases = {max_increases},",
                    f"            base_cost = {base_cost},",
                    "        },",
                ]
            )
        lines.extend(["    },", "}", ""])

    lines.extend(["return data", ""])
    path.write_text("\n".join(lines), encoding="utf-8")
    return path


def generate_project_metadata() -> Path:
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / "metadata.lua"
    metadata = load_project_metadata()
    lines = [
        "-- 项目元数据模块，由 script/build/build_mod.py 根据 data/project.json 生成。",
        "-- 为运行时与 MCT 提供统一身份、版本、外部链接和日志文件名。",
        "-- 仅返回数据；修改项目元数据后重新构建，不直接编辑此文件。",
        "return {",
    ]
    for key, value in metadata.items():
        lines.append(f"    {key} = {lua_string(str(value))},")
    lines.extend(["}", ""])
    path.write_text("\n".join(lines), encoding="utf-8")
    return path


def generate_tsv(metadata: dict) -> tuple[Path, Path]:
    CACHE.mkdir(parents=True, exist_ok=True)
    effects_path = CACHE / "effects.tsv"
    junctions_path = CACHE / "ritual_junctions.tsv"

    rows = [
        (ritual_key, effect_key)
        for faction in metadata.values()
        for ritual_key, effect_key, _rate, _max_increases, _base_cost in faction["rituals"]
    ]

    with effects_path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(["effect", "icon", "priority", "icon_negative", "category", "is_positive_value_good"])
        writer.writerow(["#effects_tables;3;db/effects_tables/wh3_ccc_effects", "", "", "", "", ""])
        for _ritual_key, effect_key in rows:
            writer.writerow([effect_key, "icon_blank.png", 0, "icon_blank.png", "campaign", "false"])

    with junctions_path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(["bonus_value_id", "effect", "ritual"])
        writer.writerow([
            "#effect_bonus_value_ritual_junctions_tables;0;db/effect_bonus_value_ritual_junctions_tables/wh3_ccc_ritual_costs",
            "",
            "",
        ])
        for ritual_key, effect_key in rows:
            writer.writerow(["percentage_cost_post_mod", effect_key, ritual_key])

    return effects_path, junctions_path


def generate_bundles_tsv(metadata: dict) -> Path:
    """生成 effect_bundles_tables 定义。

    create_new_custom_effect_bundle 会把传入的 key 当作
    effect_bundles 表中的基础记录来查；未定义的 key 拿不到模板，
    运行时创建 bundle 会失败。所以每个走 Lua bundle 的阵营
    都必须在自己的 pack 里提供该 bundle 的占位定义。
    """
    CACHE.mkdir(parents=True, exist_ok=True)
    bundles_path = CACHE / "bundles.tsv"
    # version 4 是 effect_bundles_tables 在 WH3 schema 中的当前版本；
    # 写成 0 会因找不到对应定义而构建失败。
    table_version = 4

    with bundles_path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow([
            "key",
            "localised_description",
            "localised_title",
            "bundle_target",
            "priority",
            "ui_icon",
            "is_global_effect",
            "show_in_3d_space",
            "owner_only",
        ])
        writer.writerow([
            f"#effect_bundles_tables;{table_version};db/effect_bundles_tables/wh3_ccc_bundles",
            "",
            "",
            "",
            "",
            "",
            "",
            "",
            "",
        ])
        for faction in metadata.values():
            bundle_key = faction.get("bundle_key")
            if not bundle_key:
                continue
            # 字段值照搬原版同类 bundle
            # wh3_dlc23_bundle_chd_unit_cap_rituals_cost_mods（同为阵营级容量费用修正）。
            writer.writerow([
                bundle_key,
                "",
                "",
                "faction",
                "0",
                "",
                "false",
                "false",
                "true",
            ])

    return bundles_path


I18 = ROOT / "i18"


def _emit_lua_table(lines: list[str], value: dict, indent: str) -> None:
    lines.append("{")
    for key, child in value.items():
        if isinstance(child, dict):
            lines.append(f"{indent}    {key} = ")
            _emit_lua_table(lines, child, indent + "    ")
            lines[-1] += ","
        else:
            lines.append(f"{indent}    {key} = {lua_string(str(child))},")
    lines.append(indent + "}")


def generate_i18_lua() -> Path:
    """生成 i18 Lua 数据文件，供 MCT 设置脚本运行时按语言切换文本。"""
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / "i18.lua"

    texts = {}
    for lang in ("en", "zh"):
        texts[lang] = json.loads((I18 / f"{lang}.json").read_text(encoding="utf-8"))

    lines = [
        "-- 双语文本模块，由 script/build/build_mod.py 根据 i18/en.json 和 i18/zh.json 生成。",
        "-- 提供 MCT 标题、选项、诊断、链接与输入验证所需的中英文文本。",
        "-- 仅返回文本树；修改对应 JSON 后重新构建，不直接编辑此文件。",
        "local i18 = {}", "",
    ]

    for lang, data in texts.items():
        lines.append(f"i18.{lang} = ")
        _emit_lua_table(lines, data, "    ")
        lines.append("")

    lines.extend(["return i18", ""])
    path.write_text("\n".join(lines), encoding="utf-8")
    return path


def add_source_files(client: RpfmMcpClient, pack_key: str, generated_lua: Path, *extra_generated: Path) -> None:
    files: list[tuple[Path, str]] = []

    for source in SRC.rglob("*"):
        if source.is_file():
            internal = source.relative_to(SRC).as_posix()
            files.append((source, internal))

    for generated in (generated_lua, *extra_generated):
        files.append((generated, "script/campaign/capacity_cost_control/" + GENERATED_LUA_PATHS[generated.name]))

    for source, internal in files:
        client.call_tool(
            "add_packed_files",
            {
                "pack_key": pack_key,
                "source_paths": [str(source)],
                "destination_paths": json.dumps([{"File": internal}], separators=(",", ":")),
                "ignore_paths": None,
            },
        )


def create_and_import_db(
    client: RpfmMcpClient,
    pack_key: str,
    table_name: str,
    file_name: str,
    tsv_path: Path,
    version: int = 0,
) -> None:
    internal = f"db/{table_name}/{file_name}"
    client.call_tool(
        "new_packed_file",
        {
            "pack_key": pack_key,
            "path": internal,
            "new_file": json.dumps(
                {"DB": [file_name, table_name, version]}, separators=(",", ":")
            ),
        },
    )
    client.call_tool(
        "import_tsv",
        {
            "pack_key": pack_key,
            "tsv_path": str(tsv_path),
            "table_path": internal,
        },
    )


def build() -> Path:
    metadata = load_metadata()
    generated_lua = generate_lua(metadata)
    effects_tsv, junctions_tsv = generate_tsv(metadata)
    bundles_tsv = generate_bundles_tsv(metadata)
    i18_lua = generate_i18_lua()

    client = RpfmMcpClient()
    client.call_tool("set_game_selected", {"game_name": "warhammer_3", "rebuild_dependencies": False})
    client.call_tool("close_all_packs", {})

    result = client.call_tool("new_pack", {})
    pack_key = result["String"]
    client.call_tool(
        "set_pack_file_type",
        {"pack_key": pack_key, "pack_file_type": json.dumps("Mod")},
    )
    client.call_tool(
        "set_dependency_pack_files_list",
        {
            "pack_key": pack_key,
            "list": json.dumps([[False, "groovy_mct.pack"]], separators=(",", ":")),
        },
    )

    add_source_files(client, pack_key, generated_lua, i18_lua, generate_project_metadata())
    create_and_import_db(client, pack_key, "effects_tables", "wh3_ccc_effects", effects_tsv, version=3)
    create_and_import_db(
        client,
        pack_key,
        "effect_bundles_tables",
        "wh3_ccc_bundles",
        bundles_tsv,
        version=4,
    )
    create_and_import_db(
        client,
        pack_key,
        "effect_bonus_value_ritual_junctions_tables",
        "wh3_ccc_ritual_costs",
        junctions_tsv,
    )
    create_and_import_db(
        client,
        pack_key,
        "rituals_tables",
        "tww3_mod_capacity_cost_control_amethyst_rituals",
        ROOT / "data" / "amethyst_rituals.tsv",
        version=4,
    )

    create_and_import_db(
        client,
        pack_key,
        "rituals_tables",
        "tww3_mod_capacity_cost_control_shangyang_rituals",
        ROOT / "data" / "bhashiva_rituals.tsv",
        version=4,
    )

    DIST.mkdir(parents=True, exist_ok=True)
    output = DIST / PACK_NAME
    client.call_tool("save_pack_as", {"pack_key": pack_key, "path": str(output)})
    shutil.copyfile(ROOT / "logo.png", output.with_suffix(".png"))
    return output


if __name__ == "__main__":
    print(build())
