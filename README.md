# ko-adarkroom · 小黑屋

[![CI](https://github.com/AnkioTomas/ko-adarkroom/actions/workflows/ci.yml/badge.svg)](https://github.com/AnkioTomas/ko-adarkroom/actions/workflows/ci.yml)

把 [A Dark Room](https://github.com/doublespeakgames/adarkroom)（Michael Townsend / doublespeakgames，MPL-2.0）完整移植为纯 Lua 的 KOReader 插件，同时可作为「月读」扩展使用。

## 功能

- 完整流程：小黑屋生火 → 建造者与村庄 → 漫漫尘途远征、世界地图、战斗与地标 → 残破战舰与制造机 → 星舰升空 → 结局与声望重开。
- 中文界面（上游中文表 + 后期内容补译）。
- 墨水屏友好：文本 + 按钮界面，按钮分页，日志可滚动，只在必要时刷新。
- 自动存档；远征途中关闭也能恢复到地图上。
- 100% 离线，无任何网络请求。
- 作为月读扩展时使用月读主题组件，首页提供入口组件。

下载：在 [Releases](https://github.com/AnkioTomas/ko-adarkroom/releases) 页面获取 `adarkroom.koplugin.zip`。

## 安装

### 作为 KOReader 插件

1. 下载并解压 `adarkroom.koplugin.zip`，把 `adarkroom.koplugin` 整个目录复制到 KOReader 的 `plugins/` 下（如 Kindle 的 `koreader/plugins/`）。
2. 重启 KOReader，主菜单「工具 → 小黑屋」进入。
3. 存档在 KOReader 设置目录的 `settings/adarkroom.lua`（实际为 DataStorage 设置目录下 `adarkroom.lua`）。

### 作为月读扩展

1. 先装好月读（book.koplugin），再按上面的方式安装 `adarkroom.koplugin`，两者都要在 KOReader 插件管理里启用。
2. 重启 KOReader。月读按 `PluginLoader.enabled_plugins` 扫描到本插件根目录的 `moon_source.lua`
   （`api = 1`，`id = "ext.adarkroom"`，`provides = { source = false, home_widgets = {...} }`，契约同月读
   `book.koplugin/source/registry.lua` 与 `examples/moonsource-demo.koplugin`）。
3. 在月读首页编辑态「添加组件」里加入「小黑屋」（图标 `local_fire_department`，在月读图标表里）。
   组件是一张跟随月读主题的卡片：火焰图标、标题和存档摘要（火堆状态、所在地、木头、人口；新游戏显示一句引子），整张卡点按进入全屏游戏；主菜单入口照常可用。
4. 从月读进入时：存档 / 设置写入 `utils.settings.getSource("ext.adarkroom")`（月读数据目录下 `.moon/settings/ext.adarkroom.lua`），
   与独立插件的存档互不影响；界面改用月读主题组件（标题栏、按钮、翻页条、提示，随月读主题切换），
   月读版本没有这些组件时自动回落到通用 KOReader 界面。

## 结构

```
adarkroom.koplugin/
  _meta.lua / main.lua          KOReader 插件入口（主菜单）
  moon_source.lua               月读扩展描述（首页入口组件）
  adarkroom/game.lua            宿主入口外观 Game.new(host):show()
  adarkroom/engine.lua          引擎：定时器、合并存盘、模块切换、渲染、Perks
  adarkroom/state.lua           状态树（原版 $SM）、收入、存档迁移
  adarkroom/events.lua          事件框架（随机调度、场景、按钮花费/奖励、延迟事件）
  adarkroom/events/global.lua   全局事件（小偷）
  adarkroom/events/room.lua     屋内事件（游牧商人、怪声、乞丐、神秘流浪者、侦察兵、大师、病人…）
  adarkroom/events/outside.lua  屋外事件（陷阱被毁、火灾、疾病、瘟疫、野兽、军队突袭）
  adarkroom/events/encounters.lua 荒野遭遇战（tools/convert_events.py 从上游生成）
  adarkroom/events/setpieces.lua  地标事件：洞穴、小镇、城市、矿场、飞船等（同上，自动生成）
  adarkroom/path.lua            漫漫尘途：整理背包、出发
  adarkroom/world.lua           世界地图：生成、移动、迷雾、水和食物、地标、回家、死亡
  adarkroom/items.lua           可建造/制作/交易物品数据（原版 Craftables / TradeGoods）
  adarkroom/outside.lua         屋外：伐木、陷阱、小屋与人口、工人分配与收入
  adarkroom/notifications.lua   通知日志与按模块排队
  adarkroom/l10n.lua            本地化，l10n/zh_cn.lua 由 tools/gen_l10n.py 从上游生成
  adarkroom/room.lua            小黑屋：火与温度、建造者、建造/制作/购买
  adarkroom/host/interface.lua  宿主接口：界面 / 定时 / 存档 / 设置 / 提示
  adarkroom/host/koreader.lua   KOReader 适配（settings/adarkroom.lua 存档）
  adarkroom/host/moon.lua       月读适配（存档放 .moon/settings/ext.adarkroom.lua，界面用月读组件）
  adarkroom/ui/screen.lua       通用文本 + 按钮界面（可滚动的文本区）
  adarkroom/ui/moon_screen.lua  月读主题界面（ui.themes.widgets.titlebar/button/text/pager）
  adarkroom/ui/moon_card.lua    月读首页卡片（存档摘要，整卡点按进入）
  adarkroom/events/executioner.lua 残破战舰（Executioner）事件（自动生成）
  adarkroom/fabricator.lua      嗡鸣的制造机：外星合金制造、蓝图
  adarkroom/ship.lua            破旧星舰：加固船身、升级引擎、起飞
  adarkroom/space.lua           太空：回合制躲陨石、结局
  adarkroom/prestige.lua / score.lua 声望（重开保留部分库存与总分）与计分
  adarkroom/l10n/zh_cn_extra.lua 上游中文表缺失的后期内容的补译
```

游戏代码只依赖 host 接口，不直接碰宿主 API。月读首页组件只是入口按钮，游戏在全屏界面里进行。

## 测试

无需 KOReader 的冒烟测试：在仓库根目录运行 `lua spec/headless.lua` 和 `lua spec/headless2.lua`（Lua 5.1 / LuaJIT / 5.4）。headless2 用虚拟时钟覆盖各阶段存档/关闭/重开、全部村庄事件、所有战斗场景（含特技、阵亡）、分页行数、结局与声望，并断言关闭后无残留定时器。
覆盖：存档迁移 → 生火 / 建造者 / 村庄 → 出发、战斗、全部地标与残破战舰事件（含敌人特技、自爆）→
丢弃菜单 → 回家解锁制造机 / 星舰 → 坠毁一次 → 升空通关 → 舰队信标结局 → 声望重开并在被毁村落取回库存
→ 按钮分页；最后用 `utils.settings` / UIManager 桩模拟月读宿主（存档、设置、主题界面优先与回落、描述文件约定）。

## 纯离线

插件不联网、不含任何在线服务。相对原版移除了：Dropbox 云存档、分享、应用商店/平台推广、
交叉推广事件（Penrose）、统计上报（原版 Engine.event 的 Google Analytics）以及外部链接；
本地化表在生成时也会过滤掉这些功能的文案（见 tools/gen_l10n.py）。
源码中仅保留 MPL-2.0 规定的许可证声明文字。

## 与原版的差异

- 战斗仍是实时的，但只在出手/命中时刷新屏幕，不做逐秒倒计时动画。
- 背包满时点拾取按钮会打开「丢弃」菜单（原版是鼠标悬停弹出）。
- 太空段改为回合制：每点一次 ⇇ ← · → ⇉ 算一回合，陨石下落一格（高处有的落两格），高度 +1，过 60 通关；
  引擎等级越高一回合横移越远。被撞船身 -1，归零坠毁回星舰。原版是 60 秒实时键盘躲避。
- 结局的应用商店链接去掉（纯离线）；结局后存档清空、只留声望，点「重启」直接开新局。
- 按钮超过一页（默认 8 行，设置项 `page_rows`）时分页，库存与通知日志区可滚动。
- 原版 bug 照搬：铁甲相关的原版问题保持原样；兴奋剂使用时不消耗；
  制造机的上限检查用了 `Math.min(0, …)`（靠按钮置灰兜底）。
- 上游中文表没有残破战舰 / 制造机等后期文案，由 `l10n/zh_cn_extra.lua` 手工补译。
- 远征途中关闭插件会保存进度，下次打开回到地图上（原版刷新网页会丢失远征）。

## 工具

- `tools/gen_l10n.py <adarkroom 源码目录> zh_cn`：从上游生成本地化表。
- `tools/convert_events.py <in.js> <out.lua> "<注释>"`：把上游事件数据（setpieces / encounters / executioner）转换成 Lua。

## 已知问题

- 太空飞行中途关闭不保存，重开回到生火间（与原版刷新网页一致）。
- 太空段期间村庄定时器照常运行，日志仍会出现屋内消息。
- 屏幕较矮时世界地图字号较小。
- 兴奋剂不消耗、制造机上限检查无效、铁甲相关问题：照搬原版行为。

## 许可证与致谢

本项目以 MPL-2.0 发布，见 `LICENSE` 与 `NOTICE`。

原作 A Dark Room © Michael Townsend / doublespeakgames（<https://github.com/doublespeakgames/adarkroom>），MPL-2.0。
本项目为其 Lua 移植作品，游戏数据与文案改编自上游源码，各源文件保留 MPL-2.0 声明。
