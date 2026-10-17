<div align="center">

<img src="logo.png" width="160" alt="Unit Capacity Cost Control logo">

# Unit Capacity Cost Control

**Configurable capacity purchase costs for Total War: WARHAMMER III**

[English](README.md) · [简体中文](README.zh-CN.md)

![Game](https://img.shields.io/badge/Total_War-WARHAMMER_III-8b0000?style=flat-square)
![Lua](https://img.shields.io/badge/runtime-Lua-2c2d72?style=flat-square&logo=lua)
![Python](https://img.shields.io/badge/build-Python_3.12-3776ab?style=flat-square&logo=python&logoColor=white)
[![License](https://img.shields.io/badge/license-AFPL_v9-blue?style=flat-square)](LICENSE)

[Install](#install) · [Settings](#settings) · [Documentation](docs/index.md) · [License](#license)

</div>

Controls capacity cost increases for **Nagash, Chaos Dwarfs, Armies of Shang-Yang, Beastmen, and Empire Amethyst units**. Beastmen coverage includes unit and three hero capacity rituals. Human players keep normal capacity purchases, unlocks, recruitment, and army progression.

## Install

1. Build `build/tww3_mod_capacity_cost_control.pack` using the [development guide](docs/development.md).
2. Copy it to the game's `data` directory and enable it in the official launcher.
3. Install and enable [MCT](https://github.com/chadvandy/mct_wh3) to configure the mod. Without MCT, vanilla prices apply.
4. Disable other packs that change the same rituals, cost bundles, or army-capacity mechanism.

## Settings

Each faction has an independent override: **0% by default**, 5%, 10%, or a positive custom percentage. Growth is linear from the base cost: at 10%, a base cost of 100 becomes `100 → 110 → 120`. Campaign setting changes recalculate prices using recorded purchases.

Existing saves import MCT settings and Amethyst, Shang-Yang, and Beastmen purchase counts from the previous mod, preserving any newer records. Unrecoverable history starts from a new baseline. Amethyst and Shang-Yang purchases rely on this mod's saved counters. To restore vanilla pricing, turn off their overrides in MCT; removing the pack can lose that history. After migration, save to a new file to keep the original.

For feedback, include the faction, capacity item, MCT settings, displayed price, and actual deduction. Optional diagnostics write `tww3_mod_capacity_cost_control_log.txt` in the game root.

## License

Original project code is licensed under the [Aladdin Free Public License, Version 9 (AFPL v9)](LICENSE). Third-party materials retain their original rights.
