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

Use a Conventional Commits title, such as `fix: correct capacity cost`, `feat(mct): show version`, or `chore(release): v1.0.1`. Describe changes and verification, or explain why testing was not performed, then complete the two checks in the PR template. Unassigned PRs are assigned to `FlanChanXwO`; ready PRs from other authors request their review, preserving existing assignments and reviews. GitHub prohibits self-review, so PRs authored by the maintainer skip the reviewer request. Validate a saved description locally:

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

`data/project.json` is the single version source. The build embeds its version, Workshop ID and repository URL in `config/metadata.lua`; MCT displays them through its native metadata APIs and the three project link buttons.

Run [Release mod](../.github/workflows/release.yml) on `main`, providing a version such as `1.0.0` without `v`. If the version changes, Actions creates a `codex/release-v<version>` branch and PR, explicitly dispatches Verify for that commit and merges only after it passes under the existing branch protection. Dispatch is asynchronous; the workflow waits up to two minutes for its run ID. An unchanged version reuses `main`. The build checks out the committed source, runs the full checks with Python 3.12 and Lua 5.4, and builds with RPFM 5.1.0 and schema commit `57a23a849fcaa805ccf3afe743bf46fd14a1a43c`. The build uses `windows-2025` and the official Windows RPFM archive; Lua 5.4.8 is compiled from official source with the runner's GCC. The Linux archive failed on Ubuntu 24.04 because `libgit2.so.1.9` was unavailable, so CI uses the locally verified Windows toolchain. Importing this repository's tables requires no game installation. Server startup has a 30-second readiness limit, with failure logs printed by the job. The resulting `release-pack` artifact includes the pack and `SHA256SUMS`.

The workflow then waits at the `release-approval` Environment. Download the artifact, verify the version/checksum and perform the in-game checks before approving **Review deployments**. No remote tag, Release or Steam upload is created before approval. After approval, Actions pushes `v<version>` for the approved source, creates a GitHub draft with the pack and checksums, uploads that same pack to Workshop item `3821170924`, then publishes the Release. It preserves the existing Workshop title, description, preview and visibility; the change note is the version. Corresponding source and build inputs are available through the tag under [LICENSE](../LICENSE).

Under Actions → General → Workflow permissions, administrators must enable **Allow GitHub Actions to create and approve pull requests**. The workflow creates, verifies and merges PRs without submitting approval reviews; the required PR and `verify` checks on `main` remain enforced. Also configure:

- `release-approval`: required reviewer `FlanChanXwO`, self-review allowed, administrator bypass disabled, deployments restricted to `main`. This job has no write permission or Steam secrets.
- `release`: deployments restricted to `main`, with `STEAM_USERNAME` and `STEAM_CONFIG_VDF` secrets. The Steam account must own the game, have permission to update the item and have accepted the Workshop agreement. `STEAM_CONFIG_VDF` is the single-line Base64 encoding of **SteamCMD's** `config/config.vdf` after a successful authenticated login on a trusted device. It is a credential; never commit it or paste it into issues, logs or chats. Do not use the desktop Steam client's configuration.

After the first interactive SteamCMD login (including password and Steam Guard), exit and run from that SteamCMD directory to send the cache directly to GitHub:

```powershell
gh secret set STEAM_USERNAME --env release --repo FlanChanXwO/tww3_mod_capacity_cost_control
[Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path 'config/config.vdf'))) | gh secret set STEAM_CONFIG_VDF --env release --repo FlanChanXwO/tww3_mod_capacity_cost_control
```

The runner installs Valve's official Linux SteamCMD in its default `~/Steam` directory, with credentials in `config/config.vdf` under that directory; SteamCMD updates itself. The login cache is written privately only during upload and deleted afterward; it is never an artifact. The cache is not guaranteed to remain valid indefinitely, and storing it as a GitHub Secret does not renew it. If Steam Guard requires reauthorization or the cache expires, log in again on a trusted device and replace the secret. The workflow does not bypass Steam Guard. An upload failure leaves the GitHub Release as a draft: fix the credentials and **Re-run failed jobs**. Retries must use source identical to the original tag; tags are never moved, and public releases cannot be overwritten. If the workflow itself needs a fix, merge it and dispatch the same version again. Only an unpublished draft can be restored: use the original tag source and download the original pack, verify its SHA256 against the draft notes and checksum file, then wait for approval again without rebuilding. The upload helper comes from the reviewed workflow commit so deployment fixes do not require moving the original tag; metadata still comes from the original tag. Publishing requires exit code 0 and either the matching item success message or the newer commit-stage Success message. If `main` advances during approval, cancel the old run and rebuild from current `main` for a new approval.

The legacy [Release record](../.github/workflows/release-record.yml) workflow is only for recording historical manual uploads and also requires approval. Use the full workflow for new releases.
