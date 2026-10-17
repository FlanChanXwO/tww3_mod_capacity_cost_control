# 更新日志 / Changelog

## [1.0.1] - 2026-10-17

### 简体中文

- 更新订阅版的 MCT 项目元数据，显示当前版本以及可点击的 Steam 创意工坊和 GitHub 图标。
- 补齐问题反馈、创意工坊、参与贡献按钮的目标地址。
- 加强链接跳转回归检查，确认点击会使用目标地址调用 Steam Overlay 打开命令。
- 通过 GitHub Actions 构建、审批并更新工坊，GitHub Release 与工坊改动说明共用本条双语日志。

### English

- Update the subscribed mod's MCT metadata to display the current version and clickable Steam Workshop and GitHub icons.
- Supply the destination URLs for the issue tracker, Workshop, and contribution buttons.
- Strengthen link regression checks to verify that clicks invoke the Steam Overlay command with the intended destination.
- Build, approve, and update the Workshop through GitHub Actions, using this bilingual entry for both GitHub Release and Workshop change notes.

## [1.0.0] - 2026-10-17

### 简体中文

- 首个正式版本，支持纳迦什、混沌矮人、上阳诸军、野兽人及帝国紫晶兵的容量购买费用设置；野兽人包含兵种和三类英雄容量。
- 各派系可在 MCT 中独立选择 0%、5%、10% 或自定义正百分比，按基础费用线性递增；关闭覆盖后恢复原版计价。
- 设置变更后按已记录的购买次数重新计算费用，保留正常购买、解锁、招募和军队容量进度。
- 自动导入旧版 MCT 设置及紫晶、上阳诸军、野兽人的购买计数，保留已有新版记录；无法恢复的历史从新基线开始记录。
- MCT 显示当前版本、Steam 工坊和 GitHub 链接，并提供问题反馈、创意工坊及参与贡献入口。
- 提供可选紫晶面板诊断，以及带云端审批、pack 校验和自动工坊上传的发布流程。

### English

- First stable release, with configurable capacity purchase costs for Nagash, Chaos Dwarfs, Armies of Shang-Yang, Beastmen, and Empire Amethyst units. Beastmen coverage includes unit and three hero capacity rituals.
- Configure each faction independently in MCT: 0%, 5%, 10%, or a custom positive percentage, with linear growth from the base cost. Disabling an override restores vanilla pricing.
- Recalculate costs from recorded purchases when settings change, preserving normal purchases, unlocks, recruitment, and army capacity progression.
- Import older MCT settings and Amethyst, Shang-Yang, and Beastmen purchase counts while preserving newer records. Unrecoverable history starts from a new baseline.
- Display the current version, Steam Workshop and GitHub links in MCT, with links for feedback, the Workshop, and contributions.
- Include optional Amethyst panel diagnostics and a release workflow with cloud approval, pack checksums, and automated Workshop uploads.
