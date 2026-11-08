# 参与 AirIsland 开发

本仓库独立维护 AirIsland。所有人工和 AI 贡献都必须先阅读 [AGENTS.md](AGENTS.md)、[设计规范](docs/DESIGN.md)与[三层架构](docs/ARCHITECTURE.md)。

## 开始

以本仓库当前 `main` 为基础创建功能分支；Codex 分支使用 `codex/` 前缀。

每个需求先解释其必要性与所属层。新活动必须明确真实来源、开始与结束、取消/失联策略、必要操作和权限。AirIsland 不接受为了填满空间而添加的常驻工具、假进度、未实现选项和装饰配置。

## 工程与构建

使用完整 Xcode 打开 `AirIsland.xcodeproj`，选择 `AirIsland` scheme。源码目录、工程、scheme、应用和主进程统一使用 AirIsland，辅助服务为 AirIslandHelper；已发行版本的 bundle ID、偏好存储键和用户数据路径保持兼容。

本机安装验证须使用固定本地签名，首次初始化与后续构建方式见[本机开发更新的固定签名](docs/UPDATES.md#本机开发更新的固定签名)。证书或私钥丢失时恢复原身份，不自动重建，也不安装中间 ad-hoc 产物。

## 三层职责

```text
活动层：真实来源、状态与生命周期
   ↓ 提交 / 更新 / 结束
调度层：优先级、合并、过期、抢占与恢复
   ↓ 单一当前活动
呈现层：收起、短暂强调、展开、交互与动效
```

实现入口分别为 `AirIsland/Activities/IslandActivity.swift`、`AirIsland/Scheduling/ActivityScheduler.swift`、`AirIsland/Scheduling/ActivityCoordinator.swift` 与 `AirIsland/Presentation/IslandPresentation.swift`。来源管理器提供活动事实，窗口与控件复用现有实现；详细依赖边界见[架构说明](docs/ARCHITECTURE.md)。

## 实现和验证

遵循活动层 → 调度层 → 呈现层；不得从来源直接控制窗口或在视图中复制调度逻辑。尽量复用已有服务和控件。设置复用四个分类，新增文案在 `AirIsland/Localizable.xcstrings` 内补齐简体中文，不依赖原仓库的 Crowdin 流程。

按 [测试说明](Tests/README.md)运行相关检查并完成 Release 构建。界面变化附渲染图或实际截图，明确其来源。模型测试不能替代真实交互验收。

### 常用检查

按改动范围选择相关测试；修改活动调度时至少运行活动测试、媒体播放测试和架构检查，修改发布脚本时另运行发布脚本测试。

```sh
bash Tests/run-activity-tests.sh
bash Tests/run-media-playback-tests.sh
bash Tests/run-music-spectrum-tests.sh
python3 Tests/check-architecture.py
python3 -m unittest discover -s .github/scripts/tests
```

若命令行当前选择的是 Command Line Tools，可为命令设置 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。

回归测试直接编译生产调度模型、媒体状态与封面转换模型，覆盖活动抢占、恢复、过期合并、切歌和封面清晰度更新；不能替代真实音乐软件、多显示器与系统权限验收。完整测试目录见 [Tests/README.md](Tests/README.md)，更新验签与发布顺序见[独立发行说明](docs/UPDATES.md)。

## 改动说明

提交或 PR 面向本仓库 `main`，说明具体问题、最终行为、三层职责、删除了哪些冗余项、已执行检查和未验证场景。保留上游署名、贡献历史和 GPL 许可。

报告问题时提供系统/应用版本、媒体来源、操作步骤、预期与实际结果；日志应先移除个人敏感信息。功能建议还应说明为什么必须出现在岛上、什么时候应该消失。
