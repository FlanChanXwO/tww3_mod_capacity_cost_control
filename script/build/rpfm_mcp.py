"""Small Streamable-HTTP MCP client for RPFM 5.1.

Examples:
    python script/build/rpfm_mcp.py call settings_get_string '{"value":"warhammer_3"}'
    python script/build/rpfm_mcp.py resource rpfm://examples/global_search
    python script/build/rpfm_mcp.py search-text data_script.pack nagash
    python script/build/rpfm_mcp.py decode-text data_script.pack script/campaign/...
"""

from __future__ import annotations

import json
import sys
import urllib.request
from pathlib import Path
from typing import Any, Iterable

ENDPOINT = "http://127.0.0.1:45127/mcp"
PROTOCOL_VERSION = "2025-06-18"
GAME_KEY = "warhammer_3"


class RpfmMcpClient:
    def __init__(self) -> None:
        self.session_id: str | None = None
        self._next_id = 1
        self._initialize()

    def _post(self, payload: dict[str, Any]) -> dict[str, Any] | None:
        body = json.dumps(payload).encode("utf-8")
        headers = {
            "Accept": "application/json, text/event-stream",
            "Content-Type": "application/json",
        }
        if self.session_id:
            headers["Mcp-Session-Id"] = self.session_id

        req = urllib.request.Request(ENDPOINT, data=body, headers=headers, method="POST")
        with urllib.request.urlopen(req, timeout=600) as response:
            self.session_id = response.headers.get("Mcp-Session-Id") or self.session_id
            text = response.read().decode("utf-8", errors="replace")

        result: dict[str, Any] | None = None
        for line in text.splitlines():
            if not line.startswith("data: "):
                continue
            raw = line[6:].strip()
            if not raw:
                continue
            candidate = json.loads(raw)
            if "id" in candidate:
                result = candidate
        return result

    def _request(self, method: str, params: dict[str, Any]) -> dict[str, Any]:
        request_id = self._next_id
        self._next_id += 1
        response = self._post(
            {
                "jsonrpc": "2.0",
                "id": request_id,
                "method": method,
                "params": params,
            }
        )
        if not response:
            raise RuntimeError(f"RPFM MCP returned no response for {method}")
        if "error" in response:
            raise RuntimeError(response["error"])
        return response["result"]

    def _initialize(self) -> None:
        result = self._request(
            "initialize",
            {
                "protocolVersion": PROTOCOL_VERSION,
                "capabilities": {},
                "clientInfo": {"name": "tww3_mod_capacity_cost_control", "version": "0.1.0"},
            },
        )
        if not self.session_id:
            raise RuntimeError("RPFM MCP initialization returned no session id")
        if result.get("protocolVersion") != PROTOCOL_VERSION:
            raise RuntimeError(f"Unexpected MCP protocol version: {result.get('protocolVersion')}")
        self._post({"jsonrpc": "2.0", "method": "notifications/initialized"})

    def call_tool(self, name: str, arguments: dict[str, Any]) -> Any:
        result = self._request("tools/call", {"name": name, "arguments": arguments})
        contents = result.get("content", [])
        if result.get("isError"):
            message = contents[0].get("text", "RPFM tool error") if contents else "RPFM tool error"
            raise RuntimeError(message)

        if len(contents) == 1 and contents[0].get("type") == "text":
            raw = contents[0].get("text", "")
            try:
                return json.loads(raw)
            except json.JSONDecodeError:
                return raw
        return result

    def read_resource(self, uri: str) -> Any:
        return self._request("resources/read", {"uri": uri})

    def select_wh3(self) -> None:
        # The schema/dependency cache is persisted by RPFM, so normal workflows do
        # not need an expensive full rebuild on every invocation.
        self.call_tool(
            "set_game_selected",
            {"game_name": GAME_KEY, "rebuild_dependencies": False},
        )

    def game_path(self) -> Path:
        value = self.call_tool("settings_get_string", {"value": GAME_KEY})
        return Path(value["String"])

    def open_pack(self, pack_name: str) -> str:
        self.select_wh3()
        pack_path = self.game_path() / "data" / pack_name
        value = self.call_tool("open_packfiles", {"paths": [str(pack_path)]})
        if "StringContainerInfo" not in value:
            raise RuntimeError(f"Unexpected open_packfiles response: {value}")
        return value["StringContainerInfo"][0]


def _empty_matches() -> dict[str, Any]:
    return {
        "anim": [],
        "anim_fragment_battle": [],
        "anim_pack": [],
        "anims_table": [],
        "atlas": [],
        "audio": [],
        "bmd": [],
        "db": [],
        "esf": [],
        "group_formations": [],
        "image": [],
        "loc": [],
        "matched_combat": [],
        "pack": [],
        "portrait_settings": [],
        "rigid_model": [],
        "schema": {"matches": []},
        "sound_bank": [],
        "text": [],
        "uic": [],
        "unit_variant": [],
        "unknown": [],
        "video": [],
    }


def _search_on_only(kind: str) -> dict[str, bool]:
    result = {key: False for key in _empty_matches() if key != "schema"}
    result["schema"] = False
    if kind not in result:
        raise ValueError(f"Unsupported search kind: {kind}")
    result[kind] = True
    return result


def _walk(value: Any) -> Iterable[Any]:
    yield value
    if isinstance(value, dict):
        for child in value.values():
            yield from _walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from _walk(child)


def _extract_paths(value: Any) -> list[str]:
    paths: set[str] = set()
    for node in _walk(value):
        if not isinstance(node, dict):
            continue
        for key in ("path", "file_path", "packed_file_path"):
            candidate = node.get(key)
            if isinstance(candidate, str) and candidate:
                paths.add(candidate)
    return sorted(paths)


def _summarize_global_search(result: Any, kind: str) -> dict[str, Any]:
    """Return a compact view of actual RPFM global-search matches."""
    if not isinstance(result, dict):
        return {"result_type": type(result).__name__}

    # RPFM 5.1 returns [GlobalSearch, Vec<RFileInfo>] in this wrapper.
    # The second member is the full pack index and must not be treated as matches.
    if "GlobalSearchVecRFileInfo" in result:
        values = result["GlobalSearchVecRFileInfo"]
        if not isinstance(values, list) or not values:
            return {
                "wrapper": "GlobalSearchVecRFileInfo",
                "value_type": type(values).__name__,
            }

        search = values[0]
        if not isinstance(search, dict):
            return {
                "wrapper": "GlobalSearchVecRFileInfo",
                "search_type": type(search).__name__,
            }

        matches = search.get("matches", {})
        kind_matches = matches.get(kind, []) if isinstance(matches, dict) else []
        return {
            "wrapper": "GlobalSearchVecRFileInfo",
            "kind": kind,
            "match_count": len(kind_matches) if isinstance(kind_matches, list) else 0,
            "sample": kind_matches[:3] if isinstance(kind_matches, list) else [],
            "paths": sorted(
                {
                    path
                    for item in kind_matches
                    for path in _extract_paths(item)
                    if path
                }
            ) if isinstance(kind_matches, list) else [],
        }
    root = result.get("GlobalSearch", result)
    if not isinstance(root, dict):
        return {"result_type": type(root).__name__}

    matches = root.get("matches", {})
    summary: dict[str, Any] = {"root_keys": sorted(root.keys()), "match_types": {}}
    if isinstance(matches, dict):
        for kind, values in matches.items():
            if kind == "schema" and isinstance(values, dict):
                values = values.get("matches", [])
            if isinstance(values, list):
                summary["match_types"][kind] = {
                    "count": len(values),
                    "sample": values[:3],
                }
    return summary


def search_text(pack_name: str, pattern: str) -> dict[str, Any]:
    client = RpfmMcpClient()
    pack_key = client.open_pack(pack_name)
    search = {
        "case_sensitive": False,
        "game_key": GAME_KEY,
        "matches": _empty_matches(),
        "pattern": pattern,
        "replace_text": "",
        "search_on": _search_on_only("text"),
        "sources": [{"Pack": pack_key}],
        "use_regex": False,
    }
    result = client.call_tool(
        "global_search",
        {"pack_key": pack_key, "search": json.dumps(search, separators=(",", ":"))},
    )
    return {
        "pattern": pattern,
        "pack": pack_name,
        "search": _summarize_global_search(result, "text"),
    }


def search_external_text(pack_path: str, pattern: str) -> dict[str, Any]:
    client = RpfmMcpClient()
    client.select_wh3()
    opened = client.call_tool("open_packfiles", {"paths": [str(Path(pack_path).resolve())]})
    pack_key = opened["StringContainerInfo"][0]
    search = {
        "case_sensitive": False,
        "game_key": GAME_KEY,
        "matches": _empty_matches(),
        "pattern": pattern,
        "replace_text": "",
        "search_on": _search_on_only("text"),
        "sources": [{"Pack": pack_key}],
        "use_regex": False,
    }
    result = client.call_tool(
        "global_search",
        {"pack_key": pack_key, "search": json.dumps(search, separators=(",", ":"))},
    )
    return {
        "pattern": pattern,
        "pack": str(Path(pack_path).resolve()),
        "search": _summarize_global_search(result, "text"),
    }


def search_db(pack_name: str, pattern: str) -> dict[str, Any]:
    client = RpfmMcpClient()
    pack_key = client.open_pack(pack_name)
    search = {
        "case_sensitive": False,
        "game_key": GAME_KEY,
        "matches": _empty_matches(),
        "pattern": pattern,
        "replace_text": "",
        "search_on": _search_on_only("db"),
        "sources": [{"Pack": pack_key}],
        "use_regex": False,
    }
    result = client.call_tool(
        "global_search",
        {"pack_key": pack_key, "search": json.dumps(search, separators=(",", ":"))},
    )
    return {
        "pattern": pattern,
        "pack": pack_name,
        "search": _summarize_global_search(result, "db"),
    }


def decode_text(pack_name: str, internal_path: str) -> Any:
    client = RpfmMcpClient()
    pack_key = client.open_pack(pack_name)
    return client.call_tool(
        "decode_packed_file",
        {"pack_key": pack_key, "path": internal_path, "source": "PackFile"},
    )


def decode_external_text(pack_path: str, internal_path: str) -> Any:
    client = RpfmMcpClient()
    client.select_wh3()
    result = client.call_tool("open_packfiles", {"paths": [str(Path(pack_path).resolve())]})
    pack_key = result["StringContainerInfo"][0]
    return client.call_tool(
        "decode_packed_file",
        {"pack_key": pack_key, "path": internal_path, "source": "PackFile"},
    )



def grep_decoded(pack_name: str, internal_path: str, pattern: str, context: int = 3) -> dict[str, Any]:
    decoded = decode_text(pack_name, internal_path)
    return _grep_text_payload(decoded, internal_path, pattern, context)


def _grep_text_payload(decoded: Any, internal_path: str, pattern: str, context: int) -> dict[str, Any]:
    payload = decoded.get("TextRFileInfo", []) if isinstance(decoded, dict) else []
    if not payload or not isinstance(payload[0], dict):
        raise RuntimeError(f"Expected TextRFileInfo for {internal_path}, got {type(decoded).__name__}")

    contents = payload[0].get("contents", "")
    lines = contents.splitlines()
    needle = pattern.casefold()
    hits: list[dict[str, Any]] = []
    seen_ranges: set[tuple[int, int]] = set()

    for index, line in enumerate(lines):
        if needle not in line.casefold():
            continue
        start = max(0, index - context)
        end = min(len(lines), index + context + 1)
        key = (start, end)
        if key in seen_ranges:
            continue
        seen_ranges.add(key)
        hits.append({
            "line": index + 1,
            "context_start": start + 1,
            "context_end": end,
            "text": "\n".join(f"{line_no + 1}: {lines[line_no]}" for line_no in range(start, end)),
        })

    return {
        "path": internal_path,
        "pattern": pattern,
        "hit_count": len(hits),
        "hits": hits,
    }


def grep_external_decoded(pack_path: str, internal_path: str, pattern: str, context: int = 3) -> dict[str, Any]:
    decoded = decode_external_text(pack_path, internal_path)
    return _grep_text_payload(decoded, internal_path, pattern, context)


def filter_db_rows(pack_name: str, internal_path: str, pattern: str) -> dict[str, Any]:
    decoded = decode_text(pack_name, internal_path)
    payload = decoded.get("DBRFileInfo", []) if isinstance(decoded, dict) else []
    if not payload or not isinstance(payload[0], dict):
        raise RuntimeError(f"Expected DBRFileInfo for {internal_path}, got {type(decoded).__name__}")

    table = payload[0].get("table", {})
    definition = table.get("definition", {})
    fields = [field.get("name", f"column_{index}") for index, field in enumerate(definition.get("fields", []))]
    needle = pattern.casefold()
    rows: list[dict[str, Any]] = []

    for row_index, row in enumerate(table.get("table_data", [])):
        values = [
            next(iter(cell.values())) if isinstance(cell, dict) and cell else cell
            for cell in row
        ]
        if not any(needle in str(value).casefold() for value in values):
            continue
        rows.append({
            "row": row_index,
            "values": {
                fields[index] if index < len(fields) else f"column_{index}": value
                for index, value in enumerate(values)
            },
        })

    return {
        "path": internal_path,
        "pattern": pattern,
        "match_count": len(rows),
        "rows": rows,
    }


def list_external_pack(pack_path: str) -> dict[str, Any]:
    client = RpfmMcpClient()
    client.select_wh3()
    resolved = str(Path(pack_path).resolve())
    opened = client.call_tool("open_packfiles", {"paths": [resolved]})
    pack_key = opened["StringContainerInfo"][0]
    info = client.call_tool("open_pack_info", {"pack_key": pack_key})
    payload = info.get("ContainerInfoVecRFileInfo", [])
    files = payload[1] if len(payload) > 1 else []
    dependencies = client.call_tool(
        "get_dependency_pack_files_list",
        {"pack_key": pack_key},
    )
    return {
        "pack": resolved,
        "files": sorted(file_info["path"] for file_info in files),
        "dependencies": dependencies,
    }


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__.strip())
        return 2

    command = sys.argv[1]
    if command == "call":
        if len(sys.argv) != 4:
            raise SystemExit("call requires: <tool-name> '<json-arguments>'")
        client = RpfmMcpClient()
        output = client.call_tool(sys.argv[2], json.loads(sys.argv[3]))
    elif command == "resource":
        if len(sys.argv) != 3:
            raise SystemExit("resource requires: <uri>")
        client = RpfmMcpClient()
        output = client.read_resource(sys.argv[2])
    elif command == "search-text":
        if len(sys.argv) != 4:
            raise SystemExit("search-text requires: <pack-name> <pattern>")
        output = search_text(sys.argv[2], sys.argv[3])
    elif command == "search-external-text":
        if len(sys.argv) != 4:
            raise SystemExit("search-external-text requires: <pack-path> <pattern>")
        output = search_external_text(sys.argv[2], sys.argv[3])
    elif command == "search-db":
        if len(sys.argv) != 4:
            raise SystemExit("search-db requires: <pack-name> <pattern>")
        output = search_db(sys.argv[2], sys.argv[3])
    elif command == "grep-text":
        if len(sys.argv) not in (5, 6):
            raise SystemExit("grep-text requires: <pack-name> <internal-path> <pattern> [context]")
        context = int(sys.argv[5]) if len(sys.argv) == 6 else 3
        output = grep_decoded(sys.argv[2], sys.argv[3], sys.argv[4], context)
    elif command == "grep-external-text":
        if len(sys.argv) not in (5, 6):
            raise SystemExit("grep-external-text requires: <pack-path> <internal-path> <pattern> [context]")
        context = int(sys.argv[5]) if len(sys.argv) == 6 else 3
        output = grep_external_decoded(sys.argv[2], sys.argv[3], sys.argv[4], context)
    elif command == "filter-db":
        if len(sys.argv) != 5:
            raise SystemExit("filter-db requires: <pack-name> <internal-path> <pattern>")
        output = filter_db_rows(sys.argv[2], sys.argv[3], sys.argv[4])
    elif command == "decode-text":
        if len(sys.argv) != 4:
            raise SystemExit("decode-text requires: <pack-name> <internal-path>")
        output = decode_text(sys.argv[2], sys.argv[3])
    elif command == "decode-external-text":
        if len(sys.argv) != 4:
            raise SystemExit("decode-external-text requires: <pack-path> <internal-path>")
        output = decode_external_text(sys.argv[2], sys.argv[3])
    elif command == "list-pack":
        if len(sys.argv) != 3:
            raise SystemExit("list-pack requires: <pack-path>")
        output = list_external_pack(sys.argv[2])
    else:
        raise SystemExit(f"Unknown command: {command}")

    print(json.dumps(output, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
