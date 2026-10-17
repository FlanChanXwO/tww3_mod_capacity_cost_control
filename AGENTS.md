# AGENTS.md

本项目是 WH3 容量费用控制模组，支持纳迦什、混沌矮人、上阳诸军、野兽人和帝国紫晶兵。运行时使用 Lua，构建和验证使用 Python。

## 项目导航

- [ARCHITECTURE.md](ARCHITECTURE.md)：模块职责、计价方式和数据流。
- [开发指南](docs/development.zh-CN.md)：工具链、MCP、引擎注意事项、部署与发布。
- `data/project.json`：项目身份、版本和外部链接。
- `tests/`：模组长期回归；`tests/tmp/`：Git 忽略的临时验证。
- `script/build/`：构建与 RPFM；`script/ci/`：验证、GitHub 自动化及其工具测试。
- 战役模块按 `adapters/`、`config/`、`shared/`、`store/`、`utils/` 分工。

## 常用命令

在已配置 Python 环境和 `LUA` 的仓库根目录执行：

```sh
python script/ci/verify.py --skip-pack  # 回归与语法检查
python script/ci/verify.py              # 完整验证与 RPFM 打包
python script/build/build_mod.py       # 单独构建
```

产物位于 `build/tww3_mod_capacity_cost_control.pack`。完整构建需启动 RPFM server，并配置游戏路径和 schema。

## 修改提示

- 临时排查放 `tests/tmp/`，能保护核心行为的回归再整理进长期测试。
- 修改源码或数据真源，`build/generated/` 由构建生成。
- 费用与存档改动结合 Lua 回归检查购买历史、实际扣款和军队容量；游戏结果与自动检查分别记录。
- 部署前退出游戏、备份旧包，复制后核对 SHA256。

