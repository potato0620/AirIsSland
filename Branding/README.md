# AirIsland 图标

唯一设计源为 `AppIcon.icon`，可直接用 Icon Composer 打开。保留用户最终选定的蓝色背景、浅色音频波与顶部纵向模糊轮廓；Dark 外观使用黑色背景和浅色前景。其他候选稿已移出仓库。

主应用将此文件作为资源交给 Xcode 编译，保留系统材质与 Default、Dark、Mono 外观。`AirIsland/Assets.xcassets/AppIcon.appiconset` 保留相同设计的各尺寸 PNG，供旧系统兼容使用。

- `AirIsland-icon-master.png`：Composer 导出的 Default 1024 × 1024 图，用于 README 和欢迎页。
- `AirIsland-icon-dark.png`：同一设计的 Dark 导出，供欢迎页深色外观使用。
- `AirIsland/Assets.xcassets/logo2.imageset`：欢迎页的明暗两种图像。
- `AirIslandHelper/AppIcon.icns`：由同一 Composer 设计的兼容 PNG 生成，包含至 1024 像素的完整尺寸。

导出预览（在仓库根目录执行，Dark 版将 `Default` 改为 `Dark` 并更改输出文件名）：

```sh
"/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" \
  Branding/AppIcon.icon --export-image \
  --output-file Branding/AirIsland-icon-master.png \
  --platform macOS --rendition Default \
  --width 1024 --height 1024 --scale 1 --design-generation 27
```

兼容 PNG 的图形占画布约 80%，保留 macOS 图标外侧透明边距；16–256 像素优先采用 Xcode 自动生成的 ICNS 图像，其余尺寸从原生导出缩放。修改设计后应同步上述资源，再完整构建并签名。
