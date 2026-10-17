# Development guide

[English](development.md) · [简体中文](development.zh-CN.md)

## Toolchain

| Tool | Purpose |
|------|---------|
| [Python 3.12](https://www.python.org/downloads/) | Virtual environment, tests, data generation, and builds |
| [Lua 5.4](https://www.lua.org/download.html) | Runtime regressions; precision cases use `string.pack/unpack` |
| [RPFM 5.1.0](https://github.com/Frodo45127/rpfm/releases) | Game scripts, DB inspection, and pack creation |
| [Git](https://git-scm.com/downloads) | Version control |
| WH3 and relevant DLC | Vanilla data and in-game checks |
| [MCT](https://github.com/chadvandy/mct_wh3) | Settings and campaign configuration checks |
| [Lua Language Server](https://github.com/LuaLS/lua-language-server) | Recommended for navigation and diagnostics |

Run from the repository root:

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
$env:LUA = (Get-Command lua -ErrorAction Stop).Source
& $env:LUA -v
```

In RPFM, select `warhammer_3` and configure the game path, schema, and dependency cache. Confirm that `db.pack` decodes correctly. Add the RPFM installation directory to PATH and start its server if needed:

```powershell
Start-Process -FilePath 'rpfm_server.exe' -WindowStyle Hidden
Test-NetConnection 127.0.0.1 -Port 45127
```

## Recommended MCP servers

| MCP | Setup | Use |
|-----|-------|-----|
| [RPFM MCP](https://github.com/Frodo45127/rpfm/tree/master/rpfm_server) | Add Streamable HTTP endpoint `http://127.0.0.1:45127/mcp` | Vanilla references, DB, and pack inspection |
| [Serena](https://github.com/oraios/serena) | Follow the [client setup guide](https://oraios.github.io/serena/02-usage/030_clients.html) | Symbols, references, and diagnostics |
| [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) | Install its release and register it with the client | Module relationships and impact analysis |

The Python build connects to RPFM through `script/build/rpfm_mcp.py`. Keep extracted game and reference-mod files in `.cache/reference/`.

## Editing

See [ARCHITECTURE.md](../ARCHITECTURE.md) for module responsibilities.

| Source | Content |
|--------|---------|
| `src/script/campaign/capacity_cost_control/` | `adapters/`: faction behavior; `config/`: settings; `shared/`: pricing; `store/`: purchase records; `utils/`: math and diagnostics |
| `config/constants.lua` within that directory | Fixed identifiers, precision parameters, defaults, and MCT order |
| `data/rituals.json` | Rituals, effects, base costs, vanilla rates, and limits |
| `data/project.json` | Identity, author, version, links, and log filename |
| `i18/en.json`, `i18/zh.json` | MCT text |
| `data/amethyst_rituals.tsv`, `data/bhashiva_rituals.tsv` | Vanilla ritual snapshots with DB cost scaling disabled |

Ritual rows use `[ritual_key, effect_key, vanilla_rate, max_increases, base_cost]`. Edit source files, then regenerate Lua and TSV outputs in `build/generated/`. Runtime constants are read-only by convention; Chaos Dwarf increments and bundles come from `hellforge`.

## Engine notes

Check local vanilla scripts, DB, and the installed MCT before changing engine calls.

- Campaign modules use `core:load_global_script`; MCT settings use explicit `loadfile` paths and check `get_mct()` first.
- WH3 does not support the fourth `string.find` argument or provide `math.huge`.
- Zero-delay callbacks run synchronously. Use a positive delay to read results after vanilla listeners, and cover both listener orders.
- Keep integer rounding and float32 compensation intact. Purchase history and army capacity are separate state.

## Validation

```powershell
# Tests, data generation, Python compilation, and Lua syntax
.\.venv\Scripts\python.exe script/ci/verify.py --skip-pack
# Include the RPFM pack build
.\.venv\Scripts\python.exe script/ci/verify.py
# Build only
.\.venv\Scripts\python.exe script/build/build_mod.py
# Inspect the resulting pack
.\.venv\Scripts\python.exe script/build/rpfm_mcp.py list-pack build/tww3_mod_capacity_cost_control.pack
```

Mod tests are collected from top-level `tests/test_*.py`; automation tests live in `script/ci/tests/`. Put temporary regressions and diagnostics in the Git-ignored `tests/tmp/`. Move stable checks that protect core behavior into the long-term suite.

```powershell
python -m unittest discover -s tests/tmp -p 'test_*.py' -v
& $env:LUA tests/tmp/example.lua
```

Lua runtime regressions require an interpreter. Skipped tests do not count as verified behavior.

## Pull requests

Describe changes and verification, or explain why testing was not performed, then complete the two checks in the PR template. Validate a saved description locally:

```sh
python script/ci/check_pr_template.py --body-file pr-body.md
```

## Deployment and releases

Older saves import MCT settings and the three scripted purchase histories, preserving newer records. Validate migration with an original old save, then save to a new file to keep the original.

Exit WH3, back up the previous pack outside the game directory, and disable conflicting mods. Set `WH3_PATH` to the game installation, then copy the build and compare SHA256:

```powershell
$gameData = Join-Path $env:WH3_PATH 'data'
Copy-Item 'build/tww3_mod_capacity_cost_control.pack' $gameData
Get-FileHash 'build/tww3_mod_capacity_cost_control.pack' -Algorithm SHA256
Get-FileHash (Join-Path $gameData 'tww3_mod_capacity_cost_control.pack') -Algorithm SHA256
```

Check all five factions: settings, displayed prices and actual deductions, capacity or stock gains, save/load, and disabling overrides. Retain the Nagash 85, Amethyst 1000, and Shang-Yang 50 cases, plus Beastmen old-save history and Shang-Yang army progression.

Enable diagnostics in MCT when needed. Logs are written to `tww3_mod_capacity_cost_control_log.txt` in the game root. Report game/mod/MCT versions, faction, capacity item, rate, displayed price, actual deduction, and conflicting mods.

Release order: full local validation → in-game acceptance → Workshop update through the official launcher → [GitHub Release record](../.github/workflows/release-record.yml) with an existing version tag, Workshop ID, and pack SHA256. Distribute corresponding source and build inputs under [LICENSE](../LICENSE).
