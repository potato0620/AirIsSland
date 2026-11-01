# 回归与验收

需要选择完整 Xcode；也可以给命令设置 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。

```sh
bash Tests/run-activity-tests.sh
bash Tests/run-media-playback-tests.sh
python3 Tests/check-architecture.py
bash Tests/run-island-transition-tests.sh
bash Tests/run-island-artwork-tests.sh
python3 -m unittest discover -s .github/scripts/tests
```

## 活动与架构

活动测试直接编译生产 `IslandActivity`、`ActivityScheduler` 和 `IslandPresentation`，不依赖 SwiftUI 或下载包。使用确定性时间验证：空闲、持续活动结束、系统反馈抢占与音乐恢复、按键合并、不同反馈替换、优先级、隐藏活动过期不补播、快速切换和呈现映射。

架构脚本限制活动模型/调度目录的依赖，防止重新启用原有的两条展示状态旁路。这是静态辅助检查，不是完整 Swift 依赖分析；新增业务来源与视图仍需按三层规范人工审查。

## 媒体与封面

媒体测试直接编译生产流读取器、状态模型与封面转换模型，覆盖分片 UTF-8、巨大封面、完整/增量/空快照、播放时间戳、EOF、取消、无效消息、网易云暂停/清空/队列元数据的序列、旧歌曲异步结果及高清封面原位更新。

这些检查不启动音乐应用，不能替代真实播放验收。

## 动画轮廓回归

`bash Tests/run-island-transition-tests.sh [截图输出目录]` 在独立的离屏原生窗口中运行生产背景、轮廓与统一动画策略，不访问音乐来源或用户偏好。检查三种收起高度、展开/收起、快速反向、过渡中的背景内容更新及减少动态效果；直接读取中间帧像素，验证圆角仍然存在、封面没有越界、顶部保持纯黑和尺寸连续变化。它覆盖裁剪与动画事务回归，完整 `ContentView` 和真实鼠标/触控板交互仍需另行验收。

`bash Tests/run-island-artwork-tests.sh` 构建生产 `ContentView` 的独立测试副本，以当前显示器参数逐帧检查精简/展开、横向歌曲速览/展开、快速反向和高清封面更新。测试副本关闭真实来源启动，使用独立偏好域；生产视图和调度代码保持原样，只插入封面出现次数计数及减少动态效果的测试输入。用浅色封面像素验证持续单实例、圆角、无文字黑框遮挡及封面和岛的缩放进度一致，分别覆盖有/无光晕。启用真实网易云应用角标，检查其在过渡中始终附着于封面右下角，收起和系统反馈状态不残留角标；因此运行该检查需安装网易云音乐。构建日志和截图保留在 `build/checks/artwork-render-tests/`；可通过 `AIRISLAND_DERIVED_DATA` 和 `AIRISLAND_SOURCE_PACKAGES` 复用已有构建/包缓存。这仍是离屏验证，不能代替真实鼠标、触控板和音乐应用验收。

## 界面和真实应用验收

Release 构建必须通过。影响界面的变更还需验证：

- 设置四分类、活动子页返回、中文文案、窗口最小尺寸。
- 展开音乐与文件暂存的不同宽度，长歌曲名、暂停和无播放内容。
- 连续切歌，高清封面到达只更新一次，不重复翻转。
- 播放中调音量/亮度，短暂反馈结束后恢复音乐；展开时反馈留在顶部。
- 活动开关即时生效，辅助功能拒绝后可恢复；首次使用不再请求已移除的权限。
- 全屏、无刘海屏、多显示器、减少动态效果、拖放/分享防误收起。

提交说明必须分别记录模型测试、构建、离屏渲染和真实应用操作；未执行的项目明确标记，不能用“测试通过”概括全部验收。
