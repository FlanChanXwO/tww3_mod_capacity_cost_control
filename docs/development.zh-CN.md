# 开发指南

[English](development.md) · [简体中文](development.zh-CN.md)

## 工具链

| 工具 | 用途 |
|------|------|
| [Python 3.12](https://www.python.org/downloads/) | 虚拟环境、数据生成、测试与构建 |
| [Lua 5.4](https://www.lua.org/download.html) | 执行 Lua 回归；精度测试使用 `string.pack/unpack` |
| [RPFM 5.1.0](https://github.com/Frodo45127/rpfm/releases) | 读取游戏脚本和 DB、打包、检查产物 |
| [Git](https://git-scm.com/downloads) | 版本管理 |
| WH3 + 相关 DLC | 原版资料与游戏验收 |
| [MCT](https://github.com/chadvandy/mct_wh3) | 配置界面与设置变更验收 |
| [Lua Language Server](https://github.com/LuaLS/lua-language-server)（推荐） | 代码跳转与诊断 |

### 创建环境

在仓库根目录执行：

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
$env:LUA = (Get-Command lua -ErrorAction Stop).Source
& $env:LUA -v
```

### 配置 RPFM

1. 解压包含 `rpfm_ui.exe` 和 `rpfm_server.exe` 的发行包。
2. 在 UI 选择 `warhammer_3`，配置游戏路径、schema 和依赖缓存，确认能解码 `db.pack`。
3. 将 RPFM 安装目录加入 PATH。复用 UI 已启动的 server；尚未启动时执行：

```powershell
Start-Process -FilePath 'rpfm_server.exe' -WindowStyle Hidden
Test-NetConnection 127.0.0.1 -Port 45127
.\.venv\Scripts\python.exe script/build/rpfm_mcp.py call settings_get_string '{"value":"warhammer_3"}'
```

游戏路径下应有 `data/db.pack` 和 `data/data_script.pack`；MCT 和参考 mod 从 Steam Workshop 目录读取。提取内容放 `.cache/reference/`。

## 推荐 MCP

| MCP | 安装与连接 | 用途 |
|-----|------------|------|
| [RPFM MCP](https://github.com/Frodo45127/rpfm/tree/master/rpfm_server) | 客户端添加 Streamable HTTP 地址 `http://127.0.0.1:45127/mcp` | 原版资料查询、构建与解包 |
| [Serena](https://github.com/oraios/serena) | 按[客户端指南](https://oraios.github.io/serena/02-usage/030_clients.html)安装并接入 | 符号、引用与诊断 |
| [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) | 下载对应平台的 Release，按随包说明安装并注册客户端 | 模块地图、调用关系与影响分析 |

Python 构建通过 `script/build/rpfm_mcp.py` 连接 RPFM。

## 编辑入口

模块关系见 [ARCHITECTURE.md](../ARCHITECTURE.md)。

| 内容 | 文件 |
|------|------|
| 派系行为、配置、共享计价、购买记录及辅助计算 | `src/script/campaign/capacity_cost_control/` 下的 `adapters/`、`config/`、`shared/`、`store/`、`utils/` |
| 固定标识、精度参数、费率预设、MCT 默认值与顺序 | 上述目录中的 `config/constants.lua` |
| 仪式、基础费用、原版费率与上限 | `data/rituals.json` |
| 项目身份、作者、版本、仓库/工坊地址与日志名 | `data/project.json` |
| 双语文本 | `i18/en.json`、`i18/zh.json` |
| 原版仪式行快照 | `data/amethyst_rituals.tsv`、`data/bhashiva_rituals.tsv` |

仪式数组顺序为 `[ritual_key, effect_key, vanilla_rate, max_increases, base_cost]`。Lua 常量按只读约定使用；混沌矮人的原版增量和 bundle 从 `hellforge` 实时读取。

编辑真源后重新构建；`build/generated/` 中的 Lua 和 TSV 由构建生成。修改双语文本时核对键集和生成结果，原版 fixture 与费用预期保持独立。

## 引擎约束

修改接口前，核对本机原版脚本、DB 和已安装的 `groovy_mct.pack`，确认调用者、加载环境、参数与事件顺序。

- Campaign 用 `core:load_global_script`，MCT settings 用 `loadfile`，调用前检查 `get_mct()`。
- WH3 禁用 `string.find` 第四参数，且未提供 `math.huge`。
- 零延迟回调同步执行；读取原版更新后的值使用正延迟，并测试两种监听顺序。
- 费用验证整数取整与 float32 精度；购买历史和军队容量分别维护。

## 验证

设置 `LUA` 后执行：

```powershell
# 回归、生成数据、Python 编译和 Lua 语法检查
.\.venv\Scripts\python.exe script/ci/verify.py --skip-pack

# 完整验证并构建 pack
.\.venv\Scripts\python.exe script/ci/verify.py

# 单独构建
.\.venv\Scripts\python.exe script/build/build_mod.py

# 检查 pack 文件清单和依赖
.\.venv\Scripts\python.exe script/build/rpfm_mcp.py list-pack build/tww3_mod_capacity_cost_control.pack
```

| 检查 | 位置 |
|------|------|
| 费用、计数、存读档、AI、无 MCT 和军队容量 | `tests/test_runtime.py`、`tests/lua/` |
| DB、bundle 与身份生成 | `tests/test_build_outputs.py` |
| WH3 安全契约 | `tests/test_source_contracts.py` |
| PR 正文、Issue 标签与指派、Release 登记 | `script/ci/tests/` |

临时排查、一次性诊断和探索性验证放 `tests/tmp/`（Git 忽略）；稳定且能保护核心行为的回归再整理进长期测试。默认验证只收集 `tests/` 顶层的 `test_*.py`，工具测试另从 `script/ci/tests/` 收集。

```sh
# 显式运行临时 Python 测试
python -m unittest discover -s tests/tmp -p 'test_*.py' -v
# 显式运行临时 Lua 脚本（PowerShell）
& $env:LUA tests/tmp/example.lua
```

Lua 运行回归需要解释器，跳过的测试不算验证通过。

## 提交 PR

PR 标题使用 Conventional Commits 前缀，例如 `fix: 修正费用`、`feat(mct): 显示版本`、`chore(release): v1.0.1`。填写变更点和验证步骤；未测试时说明原因，并完成 PR 模板中的两项清单。未指派的 PR 自动指派给 `FlanChanXwO`；非本人提交的就绪 PR 自动请求其审查，保留已有指派和审查选择。GitHub 禁止作者审查自己的 PR，因此本人创建的 PR 跳过 reviewer。

将 PR 正文保存为文件后，可在本地检查：

```sh
python script/ci/check_pr_template.py --body-file pr-body.md
```

## 部署与验收

旧版存档会自动导入 MCT 设置和三类脚本购买计数，已有新版记录优先。用原始旧档验收迁移，并另存新文件保留原档。

将环境变量 `WH3_PATH` 设为游戏安装目录。保存并完全退出 WH3，备份现有 pack 到游戏目录外，移走旧名称包，再复制产物并核对 SHA256：

```powershell
$gameData = Join-Path $env:WH3_PATH 'data'
Copy-Item 'build/tww3_mod_capacity_cost_control.pack' $gameData
Get-FileHash 'build/tww3_mod_capacity_cost_control.pack' -Algorithm SHA256
Get-FileHash (Join-Path $gameData 'tww3_mod_capacity_cost_control.pack') -Algorithm SHA256
```

停用冲突包后检查：

- 五项 MCT 设置的保存、重载、预设、自定义 100% 和关闭恢复。
- 连续购买的标价、实扣与容量/库存，重点检查纳迦什 85、紫晶 1000、上阳诸军 50。
- 上阳诸军后续军队容量和领主招募，野兽人旧档及三类英雄费用。
- 存读档后的计数与价格。

诊断在 MCT 开启，日志位于游戏根目录 `tww3_mod_capacity_cost_control_log.txt`，格式为 `引擎时间 | [tww3_mod_capacity_cost_control] | 事件源: 内容`。反馈附游戏/mod/MCT 版本、容量项目、费率、标价、实扣和冲突包状态。自动检查与游戏实测分别记录。

## 发布

订阅版的维护从 GitHub 完成：合并代码和对应版本的双语 CHANGELOG，调度发布工作流并完成云端审批；无需本机复制 pack 或再用启动器上传。订阅端由 Steam 下载更新，已经运行的游戏需完全退出并在下载完成后重新启动。验收时核对 MCT 首页版本、Steam/GitHub 图标与三个链接按钮；订阅目录的 pack 尚未更新时，即使源码已经修复，游戏仍会显示旧内容。

版本唯一来源为 `data/project.json`，构建会将版本、工坊 ID 和仓库链接写入包内 `config/metadata.lua`。MCT 使用原生版本与链接接口显示这些数据；右侧三个按钮分别打开问题反馈、工坊和仓库。

在 GitHub Actions 运行 [Release mod](../.github/workflows/release.yml)，分支选择 `main`，版本输入 `1.0.0` 这样的三段数字，不加 `v`。若版本变化，流程先建立 `codex/release-v<版本>` 分支和版本 PR，显式调度该提交的 Verify，通过后按现有分支保护合并；版本相同时直接复用 `main`。调度异步入队，最多等待两分钟获取验证 run ID。构建固定到已合并的提交，使用 Python 3.12、Lua 5.4 和 RPFM 5.1.0 完整验证、生成 pack，并保存 `release-pack` artifact 和 SHA256。构建使用 `windows-2025` runner 和官方 Windows RPFM 包；Lua 5.4.8 从官方源码用 runner 已有 GCC 编译。Linux 发行包在 Ubuntu 24.04 实测缺少 `libgit2.so.1.9`，因此采用与本机验证一致的 Windows 工具链。云端使用固定 schema 提交 `57a23a849fcaa805ccf3afe743bf46fd14a1a43c`；只导入仓库提供的表，无需游戏安装目录。RPFM server 启动最多等待 30 秒，失败日志随 job 输出。

构建通过后停在 `release-approval` Environment。下载 artifact、核对版本和校验和并完成游戏验收，再由维护者在 Actions 的 **Review deployments** 批准。审批前不创建远端 tag、GitHub Release 或上传 Steam。审批后推送指向获批源码的 `v<版本>` tag，创建附带 pack 与 `SHA256SUMS` 的 GitHub 草稿，上传同一 pack 到既有工坊条目 `3821170924`，成功后公开 Release。工坊标题、描述、封面、可见性保持原状，变更说明原样使用 `CHANGELOG.md` 中对应版本的中文和英文段落（含版本标题），不再仅写版本号。发布前必须补齐该版本的双语条目；缺失、重复或语言段落为空时准备阶段失败。准备阶段提取并保存 `release-notes` artifact，与 pack 一起等待审批，GitHub Release 也使用相同说明并附加校验和与工坊地址。源码与构建输入随 tag 提供，分发遵循 [LICENSE](../LICENSE)。

仓库管理员需在 Actions → General → Workflow permissions 允许 Actions 创建 PR（界面选项为 Allow GitHub Actions to create and approve pull requests）。流程只创建、验证和合并 PR，不替人提交批准评审；`main` 的 PR 和 `verify` 要求继续生效。另需配置两个 Environment：

- `release-approval`：Required reviewers 为 `FlanChanXwO`，允许本人审批，禁用管理员绕过，部署分支仅 `main`。审批 job 无仓库写权限，也不读取 Steam secrets。
- `release`：部署分支仅 `main`；保存 `STEAM_USERNAME` 和 `STEAM_CONFIG_VDF` 两个 secrets。账号必须拥有游戏及该工坊条目的更新权限，并已接受 Steam Workshop 条款。`STEAM_CONFIG_VDF` 是在可信设备用 Valve 官方 SteamCMD 成功登录后，`config/config.vdf` 文件的单行 Base64；不能使用桌面 Steam 客户端的同名文件，也不要提交或粘贴进 Issue、日志或聊天。它是登录凭据，不是加密后的公开配置。

首次登录 SteamCMD 时按提示输入密码和 Steam Guard，再退出。在该 SteamCMD 目录中，可直接把配置送入 GitHub Secret，避免落盘第二份凭据：

```powershell
gh secret set STEAM_USERNAME --env release --repo FlanChanXwO/tww3_mod_capacity_cost_control
[Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path 'config/config.vdf'))) | gh secret set STEAM_CONFIG_VDF --env release --repo FlanChanXwO/tww3_mod_capacity_cost_control
```

云端从 Valve 官方地址安装会自行更新的 Linux SteamCMD 到默认 `~/Steam`，缓存写入同目录下的 `config/config.vdf`；登录缓存仅在上传步骤写入临时 runner 的私有文件，结束时删除，不进入 artifact。缓存不保证永久有效，也不会因存入 GitHub Secret 自动续期。Steam Guard 要求重新授权或缓存过期时，在可信设备重新登录，再更新 secret；工作流不会自动绕过 Steam Guard。批准后若上传失败，保留 GitHub 草稿，修复凭据后选择 **Re-run failed jobs**：只接受源码与原 tag 完全一致的重试，不移动既有 tag。若需要修复工作流本身，合并修复后重新调度相同版本；流程只允许恢复尚未公开的草稿，固定原 tag 源码并下载原 pack，对照草稿记录的 SHA256 和校验和文件核验，重新等待审批，不重新打包。上传工具固定使用本次工作流提交中的已审查脚本，以便修复发布工具时无需移动原 tag；元数据仍来自原 tag。SteamCMD 必须返回 0，且输出正确条目的旧版成功消息或新版提交阶段的 Success，才会公开 GitHub Release。已公开版本不能覆盖。若审批期间 `main` 已前进，流程会停止，应取消旧运行并从最新 `main` 重新构建和审批。

旧的[发布记录工作流](../.github/workflows/release-record.yml)仅供补登记此前手工上传的历史版本，也需审批；新版本使用上述完整流程。

