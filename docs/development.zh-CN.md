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

填写变更点和验证步骤；未测试时说明原因，并完成 PR 模板中的两项清单。

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

本机完整验证与包内检查 → 游戏验收 → 官方启动器更新 Workshop → 登记 GitHub Release。

确认版本 tag 指向验收源码，再运行[发布记录工作流](../.github/workflows/release-record.yml)，填写 tag、Workshop ID 和 pack SHA256。分发按 [LICENSE](../LICENSE) 提供对应源码、数据输入、构建脚本和许可。

