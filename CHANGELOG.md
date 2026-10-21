# 更新日志 / Changelog

本日志遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。

This changelog follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

[1.1.1]: https://github.com/FlanChanXwO/tww3_mod_capacity_cost_control/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/FlanChanXwO/tww3_mod_capacity_cost_control/compare/v1.0.3...v1.1.0
[1.0.3]: https://github.com/FlanChanXwO/tww3_mod_capacity_cost_control/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/FlanChanXwO/tww3_mod_capacity_cost_control/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/FlanChanXwO/tww3_mod_capacity_cost_control/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/FlanChanXwO/tww3_mod_capacity_cost_control/releases/tag/v1.0.0

## [1.1.1] - 2026-10-21

### 简体中文

#### 修复

- 修复混沌矮人熔炉中混沌攻城巨人等容量项目在免费购买时仍显示 99 的问题。
- 修复野兽人和上阳诸军的容量页面在免费购买时残留显示 99 或 200 的问题，打开页面、切换页签和购买后显示 0。
- 补齐 Mixu Legendary Lords 血蹄英雄的容量费用适配，支持野兽人的基础费用倍率与购买递增设置，0% 时可免费购买。Mixu 仍为可选模组；接入前的血蹄购买次数无法恢复，后续购买独立记录。

### English

#### Fixed

- Fix Chaos Dwarf capacity entries, including the Chaos Siege Giant, still displaying 99 when purchases are free.
- Fix Beastmen and Shang Yang capacity pages showing placeholder costs of 99 or 200 for free purchases. Prices display 0 after opening the page, switching tabs, or purchasing.
- Add capacity cost support for the Gorehoof hero from Mixu's Legendary Lords, including Beastmen base cost and purchase growth settings. A 0% base cost allows free purchases. Mixu remains optional; earlier Gorehoof purchases cannot be recovered, and subsequent purchases are tracked separately.

## [1.1.0] - 2026-10-20

### 简体中文

#### 新增

- 五个支持派系均可在 MCT 中独立设置基础费用倍率，默认 100%；设为 0% 后，所有容量购买持续免费，不受后续费用增长影响。支持非负有限小数。
- 纳迦什新增独立的亡灵术进度倍率，按该次购买的原版费用计算贡献，不受玩家基础费用倍率和购买增长设置影响。免费购买仍可获得原版进度，设为 0% 则不贡献进度；保留原版门槛和符印奖励规则。

#### 修复

- 修复战役中打开 MCT 时设置页面无法正常显示的问题，保留现有两列布局和链接功能。
- 修复混沌矮人免费购买时界面残留显示 99 的问题，打开面板、购买和设置刷新后显示 0。

### English

#### Added

- Add an independent base cost multiplier in MCT for each of the five supported factions. The default is 100%; setting it to 0% keeps all capacity purchases free regardless of later cost growth. Non-negative finite decimals are supported.
- Add an independent Necromancy progress multiplier for Nagash. Each purchase contributes progress based on its vanilla cost, independently of player base cost and purchase growth settings. Free purchases can still grant vanilla progress, while 0% grants no contribution. Vanilla thresholds and sigil reward rules are preserved.

#### Fixed

- Fix the MCT settings page failing to display during a campaign, preserving the existing two-column layout and links.
- Fix Chaos Dwarf free purchases displaying the placeholder 99. Capacity prices now display 0 after opening the panel, purchasing, or refreshing settings.

## [1.0.3] - 2026-10-19

### 简体中文

- 修复进入游戏时模组可能报错并被禁用、无法正常使用的问题。

### English

- Fixed an issue where the mod could display an error and be disabled when entering the game.

## [1.0.2] - 2026-10-17

### 简体中文

#### 移除

- 移除设置页的“问题反馈”按钮，保留创意工坊与参与贡献入口。

#### 修复

- 修复订阅版在模组启动器中不显示图标的问题。
- 将纳迦什设置中的“不死军团”更正为“亡灵军团”，并调整部分中英文设置文案。
- 修复 MCT 首页 Steam 和 GitHub 图标的点击问题，避免一次点击重复打开页面，切页或重开后仍可使用。
- 修复 GitHub 图标和“参与贡献”按钮无法打开仓库的问题，点击后需在 Steam 外链确认页继续访问；创意工坊入口仍直接打开。

### English

#### Removed

- Remove the Issue tracker button from settings, keeping Workshop and Contribute.

#### Fixed

- Fix the missing launcher icon for the subscribed mod.
- Correct the Chinese name of the Legions of Undeath in the Nagash settings and adjust some Chinese and English settings text.
- Fix the MCT home page Steam and GitHub icons so a single click does not open duplicate pages and the icons continue to work after switching or reopening pages.
- Fix the GitHub icon and Contribute button failing to open the repository. Continue through Steam's external-link confirmation page to visit GitHub; Workshop still opens directly.

## [1.0.1] - 2026-10-17

### 简体中文

#### 变更

- 在 MCT 中显示模组版本，并提供可点击的 Steam 创意工坊和 GitHub 图标。

#### 修复

- 补齐“问题反馈”“创意工坊”和“参与贡献”按钮的链接地址。

### English

#### Changed

- Show the mod version in MCT with clickable Steam Workshop and GitHub icons.

#### Fixed

- Add the missing links for the Issue tracker, Workshop, and Contribute buttons.

## [1.0.0] - 2026-10-17

### 简体中文

#### 新增

- 首个正式版本，可调整纳迦什、混沌矮人、上阳诸军、野兽人及帝国紫晶兵的容量购买费用；野兽人支持兵种和三类英雄容量。
- 在 MCT 中分别设置各派系的费用增幅：0%、5%、10% 或自定义正百分比。每次购买按基础费用增加固定金额，关闭覆盖后恢复原版计价。
- 更改设置后，费用会按已有购买次数重新计算，保留购买、解锁、招募和军队容量进度。
- 沿用可读取的旧版设置，以及紫晶兵、上阳诸军和野兽人的容量购买记录，保留已有新版记录；无法恢复的历史从零开始记录。
- 在 MCT 中显示模组版本，并提供问题反馈、创意工坊及参与贡献入口。
- 可开启紫晶兵面板诊断日志，帮助排查问题。

### English

#### Added

- First stable release, with adjustable capacity purchase costs for Nagash, Chaos Dwarfs, Armies of Shang-Yang, Beastmen, and Empire Amethyst units. Beastmen support includes unit and three hero capacity types.
- Set each faction's cost increase in MCT to 0%, 5%, 10%, or a custom positive percentage. Each purchase adds a fixed amount based on the base cost. Disabling an override restores vanilla pricing.
- Changing settings recalculates costs from previous purchases while preserving purchases, unlocks, recruitment, and army capacity progress.
- Carry over readable older settings and capacity purchase records for Amethyst units, Armies of Shang-Yang, and Beastmen while preserving existing newer records. History that cannot be recovered starts from zero.
- Show the mod version in MCT with links for feedback, the Workshop, and contributions.
- Offer optional Amethyst panel diagnostic logs to help investigate problems.
