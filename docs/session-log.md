# 会话日志

本日志由 Codex、Claude 或人工共同维护。每个会话条目标题必须标注执行者：`[Codex]`、`[Claude]` 或 `[人工]`。**条目按时间倒序排列：最新条目在最顶部。** 项目级日志记录完整细节；外层 nilo 仓库 `docs/session-log.md` 只记简要条目并指向这里。

## 2026-10-03

### [Codex] · Pixy GitHub 开源发布准备

- TL;DR：把 Pixy 的构建、依赖、签名公证、安装和社区入口整理为公开可复现流程。

#### ✅ 完成

- BTree、Settings 改为公开 Swift Package，并由 `Package.resolved` 固定解析结果；移除工程中开发机绝对路径。
- 新增 FFmpegKit bootstrap 与复制脚本，固定下载地址、版本和 SHA-256；带视频运行库的通用 arm64/x86_64 Release 构建通过，8 个 framework 均进入 `Pixy.app`。
- 移除公开工程中的个人 Team ID 和默认开发签名，新增 `release.sh` 完成 Developer ID archive/export、DMG/ZIP、公证、staple、spctl 与 checksum；新增 PR/推送 CI 与 tag 发布 workflow。
- 更新公开 README、安装、构建、FAQ 和第三方许可证说明；新增 CONTRIBUTING、SECURITY、CODE_OF_CONDUCT 与首发 smoke checklist。
- 补齐 `NSAppleEventsUsageDescription`，保留图片/视频 UTI 声明并移除未使用的 Photos Library entitlement，安装文档明确默认图片应用依赖签名公证 release。

#### 验证

- `xcodebuild -list -project FlowVision.xcodeproj` 通过。
- Release 无签名构建通过；带 FFmpegKit 的干净 Release 构建通过，产物为通用 arm64/x86_64。
- `sh -n`、`plutil -lint`、`git diff --check`、`scripts/check-public-hygiene.sh` 通过。
- 全新临时 clone 等价副本 `/tmp/pixy-fresh-RrUtrP` 重新解析 `Package.resolved`，执行无 FFmpegKit 的 Release clean/build，输出 `BUILD SUCCEEDED`；依赖来源与公开卫生检查通过。构建日志移出副本后再执行卫生检查，避免把本机环境变量写入验证树。
- 复核发布脚本后改为分别提交 ZIP 与 DMG 公证，再执行 App/DMG staple，确保两种公开分发格式都有对应的公证记录。
- 只读核对 `natinli/Pixy`：仓库已公开、默认分支为 `main`、GPL-3.0；Issues 当前关闭，远端暂无 `v*` tag/Release，`main` 未启用分支保护。由于本轮未 push，新增 workflow 仍只存在本地。
- 对照上游 `netdcy/FlowVision` 的 `main` 与 1.7.6 Release：上游工程使用 Automatic Signing，实际包为 Developer ID 签名、已公证并 stapled。Pixy 工程恢复同样的 Automatic Signing 方式，Team ID 仅在本机/CI 注入，发布脚本改为 Automatic + Developer ID。
- 本机只发现 Apple Development 身份，没有 Developer ID Application 证书；`pixy-notary` 公证 profile 不存在。无签名 Release 构建已通过，真实公证包留待配置发布证书和凭据后验证。
- 用本机 Apple Development 身份尝试 Automatic Signing 失败：Xcode 对 macOS target 需要匹配的 `Mac Development` 证书，依赖包和 Pixy 均报告证书类型不匹配；未生成临时签名 App。
- 已创建被 `.gitignore` 忽略的 `LocalDev.xcconfig`，注入当前开发团队供 Xcode Automatic Signing 使用；无签名 CI 参数构建再次通过。该本机文件不进入公开仓库。
- Xcode Apple Accounts 现场确认当前只有 Personal Team，Manage Certificates 只提供 Apple Development，没有 Developer ID Application；无法在本机补齐上游 Release 所需的 Developer ID 公证链路。

#### 文档影响

- 已同步 `docs/dev/build.md`、`docs/dev/release-smoke-checklist.md`、`docs/user/installation.md`、`docs/user/faq.md`、`docs/index.md`、`CHANGELOG.md`、`THIRD_PARTY_NOTICES.md` 及仓库级贡献/安全文档。
- Developer ID 证书、notarytool 凭据、GitHub Secrets、实际公证包和 Finder 默认应用现场验收需要在发布机/仓库设置完成后补测。

## 2026-10-02

### [Codex] · Pixy 侧栏精简与 Finder 式目录展开

- TL;DR：侧栏移除不常用系统入口和 TimeMachine，默认不随当前目录自动展开层级，保留披露箭头供手动浏览。

#### ✅ 完成

- 个人收藏保留桌面、文稿、下载、用户主目录及已有自定义收藏；移除隔空投送、最近使用和应用程序。
- iCloud 分组只保留 iCloud 云盘；位置分组过滤共享、TimeMachine，仅保留本机、其他挂载卷和 OneDrive。
- `dirTreeAutoExpand` 默认关闭；侧栏目录点击只切换内容并选中目标，子目录通过披露箭头按需展开，避免当前路径长期驻留在侧栏。

#### 验证

- Release 构建通过；新进程 AX 检查确认入口列表已移除指定项目，启动时目录行保持折叠，点击桌面和子目录可正常访问，披露箭头可手动展开直接子目录。

#### 文档影响

- 已同步更新 `docs/user/usage.md`、`docs/dev/modules.md`、`docs/dev/architecture.md` 与 `CHANGELOG.md`。

### [Codex] · Pixy 侧栏选中态跟随导航入口

- TL;DR：侧栏点击保留 Finder 式灰色选中，内容区进入子文件夹后清除侧栏选中态。

#### ✅ 完成

- 在导航状态机中区分侧栏发起的目录切换与内容区／路径栏等其他入口。
- 非侧栏入口进入新目录后清除 `NSOutlineView` 选中行和 `activeSidebarEntryID`，避免灰色高亮停留在旧入口。

#### 验证

- Release 构建通过；新进程 AX 状态验证了点击桌面保留选中，内容区打开 `2025.9.20原图` 后侧栏选中态消失，截图确认左栏不再显示灰色背景。

### [Codex] · Pixy 滚动、目录层级与收起布局修复

- TL;DR：修复工具栏与缩略图滚动区重叠、目录点击后子分支长期驻留、侧栏收起后主区域留白三个问题。

#### ✅ 完成

- 主内容滚动区根据内容面板与 `window.contentLayoutRect` 的实时几何重设高度，滚动内容始终从工具栏下沿开始。
- 侧栏点击目录时展开到目标这一层，保留直接子目录入口；无关临时分支同步折叠。
- 侧栏收起时将分栏宽度置零并强制执行一次布局，内容面板填满可用宽度；重新展开恢复 238pt。

#### 验证

- Release 构建通过（仅保留既有编译警告），`git diff --check` 通过。
- 现场 AX/截图复核：滚动到中后段时内容仍位于工具栏下方；收起／重新展开侧栏时内容宽度即时重排，未出现右侧留白。
- 目录层级逻辑已按 `treeReLocate` 的祖先关系与折叠路径核对；目标层保留直接子目录入口，未对用户实际桌面目录执行全量扫描。

#### 文档影响

- 已同步更新 `docs/user/usage.md`、`docs/dev/modules.md`、`docs/dev/architecture.md` 与 `CHANGELOG.md`。

### [Codex] · Finder 侧栏现场复刻校准

- TL;DR：按本机 Finder 窗口重新校准侧栏顺序、入口和视觉密度，已补齐隔空投送、最近使用、应用程序、iCloud 云盘、共享、本机、挂载磁盘与 OneDrive；新 Release 包截图与 Finder 参考的分组布局一致。

#### ✅ 完成

- 个人收藏顺序与 Finder 对齐：隔空投送、最近使用、应用程序、桌面、文稿、下载、用户主目录；既有自定义收藏继续从原配置投影。
- 增加 iCloud 分组（iCloud 云盘、共享），位置分组按本机、Minimalist、TimeMachine、OneDrive 的 Finder 现场顺序投影；不同入口使用对应的系统线性图标。
- 固定入口复用 macOS CoreTypes 侧栏图标资源；桌面使用 Finder 同形的底部内嵌矩形，Mac mini 使用 `macmini` 四指示点图标，外置磁盘行补齐 Finder 推出按钮。
- OneDrive 位置行补充 Finder 同形的模板字形资源，并沿用系统动态颜色渲染，避免使用普通 `cloud` 符号造成品牌图标差异。
- 现场尺寸保持 Finder 基线：侧栏 238pt、正文 13pt/28pt、分组标题 11pt、16pt 图标、选择背景内缩与圆角、动态 sidebar 材质及隐藏但可滚动的滚动条。
- 启动路径定位只沿目标路径创建直接子节点，不再为侧栏预扫描用户主目录或 File Provider 后代目录。
- Release 双架构构建通过；25 条路径、虚拟入口和节点可选性断言通过；`git diff --check` 与本地化 JSON 校验通过。
- 已用新构建窗口截图与 Finder 实际窗口截图完成浅色视觉对照，截图证据保存在 `/tmp/pixy-current-window.png` 与 `/tmp/finder-window-current.png`。

#### 验证边界

- 当前 macOS 处于锁屏状态，Accessibility AX 树无法读取；窗口级截图已完成视觉比对，未将锁屏状态下的 AX 结果记作通过。深色、RTL、拖放和跨窗口交互仍需解锁后补做现场复核。

## 2026-10-01

### [Codex] · Finder 风格侧栏实现

- TL;DR：侧栏数据源、按真实路径跟随与收藏跨窗口刷新已实现；后续现场校准补充了 Finder 的 iCloud 与系统入口。

#### ✅ 完成

- 系统快捷入口、用户收藏、实际挂载卷和标签统一由共享树源构建；节点角色与入口身份隔离标题、分隔线及文件操作。
- 目录跟随按 URL 路径组件匹配，优先当前已定位的分支、最深收藏祖先、位置，启动恢复默认匹配最具体的快捷入口；虚拟标签域与真实目录匹配隔离，标签收藏复用标签角色；刷新按稳定身份恢复展开与选中。
- 侧栏上下键与鼠标共享可选性判断，跨组跳过标题、分隔线和失效入口；用户点击／展开建立分支后，成功定位才更新分支标识，启动保留空值并折叠无关临时分支，侧栏标签圆点采用系统语义色，「所有标签」使用双环图标。
- 收藏状态源发送主线程通知，各窗口订阅；原 UserDefaults 存储格式保持一致。
- plain 样式统一行几何，标题无箭头、根图标中心 25pt、正文起点 40pt，列宽固定为 viewport，侧栏初始宽 238pt；目录内容按 window.contentLayoutRect 避让工具栏，标题与首行间距 23pt、上一组末行与标题间距 37pt；28pt 正文行、蓝色线性图标、动态灰底选中、系统动态材质及 RTL 约束已接入；8pt 内容边界继续共享背景。
- Release 双架构构建通过（含最终增量构建）；从实际模型函数提取的 20 条路径规范化／祖先关系／虚拟域／节点可选性与入口排名断言通过，git diff --check 通过。
- 文档影响检查已完成：模块、架构、使用说明、CHANGELOG 回写到项目真源。

#### 待跟进

- 新包视觉、三级目录、标签、收藏跨窗口、导航历史、拖放／右键／键盘、失效路径、深色／失焦／RTL 及缩放实机检查由主会话执行，不能将构建结果视为这些场景已通过。


### [Codex] · 左侧栏 mockup 探索

- 用户确认收藏目录保留展开能力；PRD 已收敛，技术设计与实施计划已整理，等待最终规划摘要批准。文档影响检查：本轮仅规划，模块及使用说明在实现后回写。

- 用户选择 Finder 风格参考；补充细化 mockup，采用个人收藏／位置／标签分组、紧凑行距、蓝色线性图标及灰底选中态，目录展开行为待确认。

- 基于当前截图生成三份独立 mockup：分组快捷导航、聚焦当前目录、收藏优先。已查看生成结果，等待用户选择或组合方向。
- 规划记录位于外层 `.trellis/tasks/10-01-pixy-sidebar-design/prd.md`，任务保持 planning；业务代码及运行配置未修改。
- 文档影响检查：本轮是候选设计，仅记录项目日志；正式模块及用户说明在方案确定并实现后回写。

### [Codex] · 目录栏文件夹图标

- 左侧目录行显示文件夹图标、名称和展开箭头，采用既有单元格布局。
- 目录栏与内容区保留透明材质、隐藏滚动条及 8pt 单侧圆角。
- Release 构建与 git diff --check 通过；已重启 Pixy，窗口截图确认文件夹图标与文字排列。

### [Codex] · 透明侧边栏与 8pt 内容圆角

- 目录树及 scroll/clip 背景透明，隐藏横纵滚动条，保留滚动容器；地址区域前置固定留白。
- 侧边栏与内容圆角外侧共享 behindWindow/sidebar 材质；背景放在 NSSplitView 同级，并在布局时同步尺寸，铺满窗口全高。背景层不接收鼠标事件。
- 内容白面填充与面板裁剪统一使用 8pt 单侧圆角，支持 RTL，随面板尺寸更新；裁剪覆盖滚动内容。
- Release 双架构构建与 git diff --check 通过；新构建窗口截图确认材质全高铺满、上下圆角连续、地址区域右移及滚动条隐藏。
- 滚轮/触控板滚动、深色模式、RTL 和大图往返尚未完成实机复核。
- 本版改动提交到 Pixy 本地仓库。

## 2026-09-15

### [Codex] · 去除分栏间隙残留竖线，完成圆角收口

- v8 实机验证表明，移除内容面板自绘描边后仍存在一列亮色像素；像素值约为 `#f4f5f5`，与 storyboard 的 `OutlineViewBgColor` 一致，根因是 `NSSplitView` 分栏间隙露出了父级背景，而不是圆角 path 或 Dock。
- v9 将 `NSSplitView` 自身背景统一为 `NSColor.windowBackgroundColor`，并保留无描边的单侧 12px 填充圆角；新 Release 包重新启动后，竖线消失，底部 junction 只保留自然的白灰弧形过渡。用户现场确认“终于好了”。
- 构建通过，`git diff --check` 通过；代码未提交、未推送。

### [Codex] · 统一圆角外侧背景，修正材质色带

- 重新置前检查 v6 实机窗口后确认：圆角 path 已经连续，真正造成“圆角下面不干净”的是侧边栏 storyboard `NSVisualEffectView` 仍在绘制粉紫色材质，而内容 pane 弧外壳绘制的是中性窗口底色，两者在分界处形成亮竖带和色阶跳变。
- 保留 storyboard effect view 作为兼容占位但停止其绘制，在侧边栏 pane 下方加入与内容 pane 共用 `NSColor.windowBackgroundColor` 的不透明背景 view；内容 pane 仍由同一条 leading edge path 绘制填充和弧线。
- v7 Release 构建通过。实际全屏截图和窗口级截图均确认：上、下圆角只有一条连续边，弧外为统一中性灰；窗口底部紧接的深紫色与窗口边界重合，属于 Dock 上沿而非 Pixy 绘制。未提交、未推送。

## 2026-09-14

### [Codex] · 移除圆角 path 误画的底边暗线

- 用户最新复核仍指出圆角下方不干净。对比当前截图与 Chrome 参考图的逐行像素后确认：闭合内容 path 的 `stroke()` 同时描了整条底边；在 Dock 上沿之前形成一条横向突变，容易被误认为圆角外侧背景污染。
- 保留闭合 path 负责内容面填充，边框改为只绘制 leading 侧的竖线与上下两段 12pt 弧线，不再描绘顶部/底部水平边；NSSplitView 的 divider 仍只保留布局与命中区域。
- 全新 v5 Release 构建通过；窗口级截图确认应用自有圆角边界无底边暗线，全屏截图确认剩余紫色是 Dock 的系统叠层。未提交、未推送。

### [Codex] · 圆角外侧背景污染修正

- 用户反馈内容 pane 的圆角下方背景不干净。运行时对比确认：深紫色区域来自全屏截图中的 macOS Dock；Pixy 自身的弧外层此前仍使用半透明 `NSVisualEffectView`，在窗口底部会让外部颜色参与过渡。
- 将内容 pane 的弧外层改为不透明 `NSView`，直接绘制动态窗口背景色；内容白面仍由同一条 leading-edge path 绘制，scroll/clip/collection 背景继续保持透明。
- Release 构建通过；窗口级截图确认圆角外侧干净，全屏截图确认 Dock 仍是窗口外的独立叠层。未提交、未推送。

### [Claude] · 两段式 UI 重构（用户睡眠期间彻底修复并自查）

#### 最终形态（多轮迭代后）

- **两段式结构**：灰色外壳（窗口底色 = OutlineViewBgColor）+ 两张浮动圆角卡片
  - 侧边栏卡：内缩 6px、四角圆角 12、实心灰，目录树内容避让（scroll contentInsets）
  - 内容卡：内缩（上 52 留工具栏行、右/下/左 8）、四角圆角 12、白色，承载缩略图网格
  - 工具栏浮在外壳上（标题栏透明 + fullSizeContentView 常驻）
- **大图模式**：enableToolbarBlend/disableToolbarBlend 切换（不再破坏两段式结构——之前退出大图会移除 fullSizeContentView 导致 UI 变形，已修复）；底部标题胶囊方案 1（文件名实色 + 张数半透明，分色同行）；Finder 打开的会话关闭大图退出应用（isLaunchFromFile + NSApp.terminate）
- **路径条**：前置 .space 间隔，不再贴窗口边缘

#### 迭代中的弯路（记录避免重蹈）

1. 整窗透壁纸毛玻璃 → 用户否决（内容区发灰）→ 回退
2. pane 层白底 + 单角圆角 → 圆角junction 处理错（maskedCorners 单角 + insets 冲突）→ 改为浮动卡片四周留缝方案
3. disableToolbarBlend 恢复不透明标题栏 → 破坏两段式 → 改为常驻透明
4. 关键教训：NSSplitView pane 无法直接 inset；用 scrollView.layer.cornerRadius + masksToBounds + contentInsets 实现卡片化

#### 验证

- Release 构建通过；截图确认：侧边栏卡四角圆角可见、内容卡浮起、分界清晰、无壁纸渗透
- 大图往返后 UI 稳定（disableToolbarBlend 不再改窗口结构）
- Finder-quit 逻辑保留（isLaunchFromFile 检测在 closeLargeImage 最前）

#### 待跟进

- [ ] 深色模式目测验证（代码使用自适应色，预期正常）
- [ ] RTL 布局下侧边栏在右侧的表现
- [ ] push 到 GitHub

## 2026-09-13

### [Claude] · 两项 UX 优化

#### 完成

- **侧边栏毛玻璃**：storyboard 侧边栏 customView 插入 NSVisualEffectView（behindWindow + sidebar material，置于最底层）；CustomTableRowView.drawBackground 不再填充 OutlineViewBgColor 纯色改为透明，右键边框逻辑保留。明暗模式均生效。
- **Dock 图标联动（方案 A）**：closeLargeImage 开头检测 publicVar.isLaunchFromFile（Finder/外部打开图片的会话标记），命中则关窗口并 NSApp.terminate；常规浏览会话不受影响。windowWillClose 已有完整的保存/清理/terminate 链路，直接复用。
- 已知边界：customModule="FlowVision"、工程名/scheme、数据目录名保持不变（此前决策）。

#### 验证

- Release 构建通过；启动后侧边栏透出壁纸色调（vibrancy 生效），选中样式正常。
- 用户 Finder 双击图片实测：关闭大图后应用退出、Dock 图标消失，确认生效。

### [Claude] · 正式签名配置完成

#### 完成

- 完成本地签名验证；正式公开发布改用 Developer ID 证书和 Apple 公证流程。
- bundle id 使用 Pixy 的公开标识，开发机 Team ID 不写入仓库或公开文档。
- 公开源码构建默认关闭签名，发布签名由归档脚本和 CI 的受保护凭据注入。

#### 收益

- 签名身份跨构建稳定：TCC 隐私授权（访问文稿等）不再每次构建重新弹窗。
- build.md 签名一节从此可用默认命令构建（无需 CODE_SIGNING_ALLOWED=NO）。

### [Claude] · 修复菜单栏残留旧名

#### 完成

- 根因：应用菜单（关于/隐藏/退出 FlowVision）标题写死在 Main.storyboard 与两个 .xcstrings（101+51 处多语言文案）里，前两轮只改了代码与 Info.plist 未覆盖到。
- 处理：storyboard 中 UI 标题全部改为 Pixy（12 处 customModule="FlowVision" 为 TARGET 模块引用，**必须保留**，改了会白屏）；两个 xcstrings 全量替换 FlowVision→Pixy（JSON 校验通过）。
- 构建通过，编译产物 Main.storyboardc 已验证含 "About Pixy"/"Quit Pixy"。

#### 边界

- 源码中仍有少量 FlowVision：工程名/TARGET/scheme（用户决定保留）、数据目录 appendingPathComponent（避免数据迁移）、customModule 引用。

### [Claude] · 更换应用图标

#### 完成

- 应用图标替换为用户选定的 icons8 "Photo Gallery" 图标（96px 下载版放大至 1024px 写入 AppIcon.appiconset/icon.png）。
- 构建通过，Dock/应用已重启生效。

#### 边界

- 源图为 icons8 版权素材，免费许可需署名（"Icons by icons8"）；放大到 1024px 后大尺寸略糊。后续可换用 icons8 高清正版授权或原创概念稿。

### [Claude] · 仓库更名与依赖迁移

#### 完成

- GitHub 仓库更名：natinli/FlowVision → **natinli/Pixy**（gh repo rename），origin 已更新；upstream（netdcy/FlowVision）不变。
- 本地目录更名：`projects/FlowVision` → `projects/Pixy`；nilo 登记表与 .gitignore 同步更新。
- 构建依赖完成公开化整理：BTree、Settings 使用 Swift Package，FFmpegKit 使用项目脚本准备，工程不再依赖开发机绝对路径。
- 文档更新：build.md 依赖结构表、bootstrap 流程、签名公证和排障说明。

#### 验证与技术记录

- Release 构建通过（新路径实测）。
- 关键点：pbxproj 相对路径以**仓库目录**（projects/Pixy/）为基准；本仓库在 `~/Documents/nilo/projects/` 下，故到主目录需 `../../../../`（4 级）。路径深度写错时报 `the package at '...' cannot be accessed`，报错信息里会显示解析后的绝对路径，可用于定位差几级。
- Git 仓库更名后旧 URL 自动重定向，但本地 origin 与文档链接应手动更新。

### [Claude] · 应用更名 FlowVision → Pixy

#### 完成

- 用户经五轮候选名筛选后选定 **Pixy**。
- 改动（仅展示名，符合 PRD 范围）：
  - pbxproj：`INFOPLIST_KEY_CFBundleDisplayName = Pixy`（Debug/Release 两处）；`PRODUCT_NAME` 从 `$(TARGET_NAME)` 改为 `Pixy`/`PixyDbg`。
  - `WindowController.swift:502` 工具栏默认标题、"DataModel.swift:896" localizedName → "Pixy"。
  - 文档品牌替换：README 双语标题与 fork 说明、CLAUDE.md、docs/index.md、installation.md、faq.md、build.md 产物路径。
  - CHANGELOG.md 顶部 Fork 条目追加更名记录。
- 未改动：bundle id（netdcy.FlowVision）、数据目录（Application Support/FlowVision）、scheme 名、仓库目录名、上游 URL、GitHub 仓库名。

#### 验证与技术记录

- Release 构建通过；启动后 Dock、菜单栏、进程 displayed name 均为 **Pixy**。
- 关键发现：`CFBundleDisplayName` 只改菜单栏/关于窗口显示；**Dock 悬停与快捷菜单用 `CFBundleName`**，它被构建系统强制写为 `$(PRODUCT_NAME)`，改 pbxproj 的 `INFOPLIST_KEY_CFBundleName` 无效（Xcode 不支持该键），源 Info.plist 加该键也会被覆盖。**唯一正规改法是设置 `PRODUCT_NAME`**——产物从 FlowVision.app 变为 Pixy.app，CFBundleName 随之变 Pixy。
- LaunchServices 缓存旧名时用 `lsregister -f <app>` + `killall Dock` 刷新。

### [Claude] · Xcode 26.3 实测构建通过

#### 完成

- 安装 Xcode 26.3（Build 17C529），`xcode-select` 已指向 /Applications/Xcode.app。
- 验证 Swift Package 依赖解析，并通过 bootstrap 脚本下载、校验 FFmpegKit 6.0 macOS xcframework（8 个 framework）。
- Release 构建成功：`xcodebuild -project FlowVision.xcodeproj -scheme FlowVision -configuration Release build CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""`；产物为通用 arm64/x86_64 的 Pixy.app。

#### 验证与修正

- **修正 build.md 两处错误认知**：
  1. FFmpegKit 是**硬依赖**——工程 build phase 直接引用 8 个 xcframework，缺失时构建失败；原文档推测"缺失也能构建、仅运行期降级"是错的。dlopen 降级只发生在 xcframework 存在但无法加载的场景。
  2. 新增「签名」一节：无证书时 `CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""` 可跳过签名构建（实测通过）；正式签名需 Xcode 登录 Apple ID 选 Team。
- 常见构建问题表补充两条实测遇到的错误及解法。

### [Claude] · 建立中文文档体系

#### 背景

- 本仓库 fork 自 netdcy/FlowVision（上游 1.7.6），由 natinli/Pixy 维护。
- 仓库原有文档仅面向最终用户的 README.md/README_zh.md（英文/中文）和 docs/ 下 3 张预览图，无开发向文档。
- 用户要求：完全重新设计、覆盖全面、便于长期维护的全中文文档体系，含用户文档与开发/AI 协作文档；新增 CHANGELOG；完全重写 README；项目内建立更细粒度的会话日志。

#### 完成

- 深读源码 53 个 Swift 文件，研究笔记存于 nilo 仓库 `.trellis/tasks/09-13-flowvision-docs/research/source-notes.md`。
- 新建 `CLAUDE.md`：AI 协作入口（仓库性质、remote 布置、协作约定、文档地图、环境注意）。
- 新建 `CHANGELOG.md`：基于上游 36 个 release（1.0.2 → 1.7.6）整理的中文版本历史，顶部设「Fork」条目记录本仓库改动。
- 完全重写 `README.md` 与 `README_zh.md`：结构对齐新文档体系（功能特性、安装、快速上手、文档导航），双语互相链接，保留上游支持/许可证信息。
- 新建 `docs/index.md`：文档中心总入口 + 硬性维护规则表（哪类改动须更新哪份文档）。
- 新建用户文档 `docs/user/`：installation.md（三种安装方式 + quarantine 处理）、usage.md（四种视图、手势、快捷键、视频、标签评级、设置全览）、faq.md（损坏提示、HDR/RAW、性能、标签等排查）。
- 新建开发文档 `docs/dev/`：architecture.md（模块地图、核心数据流、全局状态组织、缓存去重、唯一真源清单）、modules.md（逐目录逐文件职责与关键接口）、build.md（依赖结构、FFmpegKit、构建步骤、xcconfig、调试、常见问题）、contributing-internal.md（代码约定、常见改动落点、上游同步策略、提交约定）。

#### 验证与边界

- 文档中全部源码路径基于实际勘察（53 文件清单逐目录盘点），模块职责经子代理逐文件深读后撰写。
- 工程引用仓库外本地依赖，build.md 写明目录布置要求。
- 未改动任何上游源码。

#### 待跟进

- [x] 安装完整 Xcode 后实测构建命令（当日完成）。
- [x] 首次 push 到 origin（natinli/Pixy，d16f20e..b90472b 已推送）。
- [ ] 上游发布新版本时按 contributing-internal.md 的同步策略合并。
