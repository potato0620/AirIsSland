<p align="center"><img src="Branding/AirIsland-icon-master.png" width="160" alt="AirIsland 图标"></p>
<h1 align="center">AirIsland · 轻岛</h1>
<p align="center">Mac 上轻量的实时活动入口。</p>

[下载最新版本](https://github.com/potato0620/AirIsSland/releases/latest) · [设计与活动规范](docs/DESIGN.md) · [三层架构](docs/ARCHITECTURE.md) · [AI 开发规范](AGENTS.md) · [贡献指南](CONTRIBUTING.md)

## Air 的含义

**没有活动时安静收起，有活动时一眼看懂，需要操作时轻轻展开。**

AirIsland 借鉴 [Apple Live Activities 与灵动岛设计指南](https://developer.apple.com/design/human-interface-guidelines/live-activities)：围绕有开始和结束的活动，提供简洁、及时的信息与必要操作。我们将这些原则适配 Mac 的鼠标、键盘、多显示器和刘海区域。这是独立实现的 macOS 应用，并非 Apple 的系统灵动岛或 ActivityKit 插件平台。

岛是活动入口，不是另一个桌面、应用启动器或工具箱。不会为了填满空间而常驻日历、天气、聊天记录或无意义动画；空闲就是一种完整状态。

## 当前范围

| 能力 | 岛上的行为 |
| --- | --- |
| 音乐 | 统一使用系统“当前播放”读取网易云等应用的播放状态；收起时展示状态，主动展开后提供封面、进度和必要控制 |
| 系统反馈 | 调节音量、显示器亮度、键盘背光时，在岛内短暂反馈并自动收回 |
| 电源变化 | 插拔电源或充电状态变化时短暂提示 |

已移除文件暂存、拖放接收、文件预览与分享，以及首页常驻日历、镜子、闲置人脸、歌词查询、自定义 Lottie 动画管理和播放按钮编排器。图标固定使用 AirIsland 品牌；短暂活动统一在岛内呈现。此前暂存的用户文件、书签和持久化记录保留在原位置，应用不再读取或清理这些数据。

目前没有接入 AI 服务。未来 AI 能力也只能以真实任务的进度、完成摘要或待确认操作接入；长对话、参数配置和完整结果应进入独立窗口，不提前放置空入口。

## 必须遵守的三层架构

```text
活动层：发生了什么，当前状态是什么，何时结束
   ↓ 提交 / 更新 / 结束
调度层：现在展示谁，何时收回，如何恢复被打断的活动
   ↓ 单一当前活动
呈现层：收起 / 短暂强调 / 主动展开，统一布局与交互
```

**今后的人工开发与 AI 开发都必须遵循这三层职责。** 功能来源不得直接操作岛的尺寸和动画；视图不得自行决定活动优先级或另开收起计时器。三层架构是功能接入约束，不能用“快速实现”绕过。

当前实现入口：`Activities/IslandActivity.swift`、`Scheduling/ActivityScheduler.swift`、`Scheduling/ActivityCoordinator.swift`、`Presentation/IslandPresentation.swift`，均位于 `AirIsland/` 下。现有媒体和系统管理器提供活动事实；原有窗口与具体 SwiftUI 控件继续复用。详见[职责、数据流与扩展步骤](docs/ARCHITECTURE.md)。

## 设置

设置按用户要做的事组织，不把内部架构术语暴露给用户：

- **活动**：音乐、系统反馈、电源变化的启用条件和权限。
- **显示与交互**：显示器、刘海适配、悬停、手势、快捷键和统一外观。
- **通用**：登录启动、菜单栏入口、隐私与系统兼容。
- **关于**：版本、下载更新、项目来源。

调度优先级与提示时长统一由代码管理，不提供每项活动各自选择浮层位置、动画和优先级的开关。新增活动复用活动设置列表，避免继续增加顶级分类。

## 安装

从发布页下载 DMG，将 AirIsland 拖入「应用程序」。发布包为 Apple Silicon 版本，要求 macOS 14 或更新版本。发布页表示已发布版本，仓库主分支可能包含尚未发布的改动。

当前独立发行包使用本地签名，尚未经过 Apple 公证。首次打开如被系统拦截，可在「系统设置 → 隐私与安全性」中允许打开。更新前先退出旧版应用；应用标识保持一致以保留偏好设置。已移除功能的旧偏好不再读取，无需清除所有设置。

系统反馈替换为可选功能，启用时才申请辅助功能权限。音乐统一使用系统“当前播放”，不再提供媒体来源选择或专用客户端连接；系统接口不可用时不自动切到其他来源。针对当前播放器的必要控制仍按需请求权限。应用不再申请摄像头、日历和提醒事项权限。

## 开发与验证

开始前阅读 [AGENTS.md](AGENTS.md)、[设计规范](docs/DESIGN.md)和[架构说明](docs/ARCHITECTURE.md)。使用完整 Xcode 打开 `AirIsland.xcodeproj`，选择 `AirIsland` scheme 构建。源码目录、工程、scheme、应用和主进程统一使用 AirIsland，辅助服务为 AirIslandHelper。仅已发行版本的 bundle ID、偏好存储键和文件数据路径保持兼容。

```sh
bash Tests/run-activity-tests.sh
bash Tests/run-media-playback-tests.sh
python3 Tests/check-architecture.py
python3 -m unittest discover -s .github/scripts/tests
```

若命令行当前选择的是 Command Line Tools，可为命令设置 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。

回归测试直接编译生产调度模型、媒体状态与封面转换模型。它们覆盖活动抢占、恢复、过期合并、切歌和封面清晰度更新；不能替代真实音乐软件、多显示器和系统权限验收。具体见 [Tests/README.md](Tests/README.md)。

## 来源与许可

本项目基于 [TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch) 开发，感谢原作者和所有贡献者。AirIsland 由本仓库独立维护与发布。

代码遵循 [GPL-3.0 许可证](LICENSE)。原有版权声明、贡献记录以及依赖各自的许可继续保留。
