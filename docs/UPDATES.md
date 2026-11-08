# 应用内更新与独立发行

关于页和菜单栏的“检查更新…”使用同一个 Sparkle 更新器，在独立窗口内检查版本、展示说明、下载并在确认后安装重启。首次点击才启动更新器，只允许手动检查，不增加自动下载、更新渠道或岛内进度设置。

首次安装从 GitHub Release 下载 DMG 或 ZIP，将应用放入“应用程序”等可写的本机目录；从只读 DMG 直接运行时不能原地更新。

## 个人开发与签名基线

从 **2.8.19（316）** 起，维护者选择在自己的 Mac 上维护两套独立的签名：

- **App 代码签名**：使用本机已有的固定自签名证书，主应用和 AirIslandHelper 的指定要求同时固定各自 bundle ID 与证书指纹。不会因为私钥缺失自动重建身份。
- **更新包签名**：使用本机登录钥匙串中 Sparkle `AirIsland-Personal` 账户的 Ed25519 密钥，App 中仅保存公开的 `SUPublicEDKey`。私钥不写入仓库、安装包或发布说明。

按维护者明确选择，本次不保留旧更新密钥的兼容通道，2.8.19 是新基线。此前测试版本需手动安装本版，后续版本沿用本机这套密钥；开发和发布不再依赖原公司电脑。密钥不绑定硬件，但迁移或恢复时必须安全保留原私钥，不能每次发布都重新生成。

固定自签名不属于 Apple Developer ID 签名，当前安装包未经过 Apple 公证。其他 Mac 首次打开可能需要手动允许，系统权限在升级后仍可能需要重新同意；指定要求与签名检查不能替代真实权限继承验收。公开发行后续仍应迁移到 Developer ID，不能宣传为所有设备均已信任或自动保留授权。

## 更新源与验证

- 更新列表：`https://raw.githubusercontent.com/potato0620/AirIsSland/main/updater/appcast.xml`。
- 下载包：本仓库 GitHub Release 的 `AirIsland-版本-macOS-arm64.zip`，DMG 作为手动安装入口。
- App 使用内置公钥在解压前验证 Ed25519 签名。SHA256 文件用于手动核对，不能代替更新签名。
- 原有 bundle ID、偏好与用户数据路径保持兼容，不清空用户设置或 TCC 权限记录。

更新列表只包含已正式发布的稳定版本，不能加入未发布测试包或上游应用历史版本。后台检查偏好即使从旧版保留下来，也不能绕过手动检查策略。

可读取现有更新公钥核对配置，命令不会生成新密钥：

```sh
/path/to/Sparkle/bin/generate_keys --account AirIsland-Personal -p
```

更新私钥暂不可用时，可以发布手动安装包并说明应用内更新未开放，保留现有有效更新列表。新基线建立后，不得通过重新生成密钥或更换公钥绕过已发布版本的验签；应恢复原密钥。

## 本机开发更新的固定签名

初次配置新开发环境时才初始化代码签名身份：

```sh
python3 Configuration/signing/local_signing.py init
```

已有身份时不能重新创建。私钥位于当前用户钥匙串，公有证书与身份配置位于 `~/Library/Application Support/AirIsland/LocalSigning`；请安全备份钥匙串中的身份，私钥丢失时恢复原身份。工具不安装受信任根证书，不修改 Gatekeeper、TCC 或系统信任设置。

以后构建与安装验证统一使用：

```sh
bash Configuration/signing/build-local.sh
```

默认产物在 `build/local-signed/DerivedData/Build/Products/Release/AirIsland.app`。可用 `AIRISLAND_LOCAL_DERIVED_DATA` 指定构建目录、`AIRISLAND_SOURCE_PACKAGES` 复用包缓存。脚本完整构建 Release，然后从内到外对自有辅助进程和主应用签名并验证；证书或私钥缺失即失败，不回退 ad-hoc。确认最终签名通过后退出旧版再替换，不能安装或上传中间 ad-hoc 产物。

Apple Developer ID、代码签名与 Sparkle 更新签名承担不同职责。相关原理见 Apple [签名要求](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)与[代码签名任务](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html)。

## 准备公开发行包

主应用、辅助进程和发布说明统一要求 macOS 15 及以上，发布包为 Apple Silicon 版本；内置媒体适配框架的最低系统为 15.0。发布前核对每个嵌套 Mach-O 的实际最低系统与 arm64 支持，不能只读取主应用 Info.plist。使用新 SDK 构建不等于已完成旧系统真机验收。

先同步 `main` 与最新已发布更新列表，递增主应用与辅助服务的版本、构建号，运行相关回归，再完整构建 Release。构建号必须大于所有已发布条目，营销版本使用稳定的 `major.minor.patch`。禁止在构建后直接改版本号而不重新签名。

2.8.19 使用以下固定自签名构建方式：

```sh
AIRISLAND_LOCAL_DERIVED_DATA="$PWD/build/releases/2.8.19/DerivedData" \
  bash Configuration/signing/build-local.sh
```

Sparkle 工具位于包缓存的 `SourcePackages/artifacts/sparkle/Sparkle/bin`，应与 `Package.resolved` 一致。用实际路径准备已签名更新 ZIP：

```sh
python3 .github/scripts/prepare_update.py \
  --app build/releases/2.8.19/DerivedData/Build/Products/Release/AirIsland.app \
  --sparkle-bin /absolute/path/to/SourcePackages/artifacts/sparkle/Sparkle/bin \
  --notes /absolute/path/to/release-notes.txt \
  --output build/releases/2.8.19/prepared-release
```

工具只接受新的输出目录，校验 bundle ID、更新源、公钥、手动检查配置、递增构建号、嵌套签名与架构；从钥匙串确认 `AirIsland-Personal` 公钥一致后，使用官方 Sparkle 工具生成并验证签名。输出 ZIP、`SHA256SUMS.txt`、`appcast.xml`，不导出私钥、不改写线上源，也不自行发布。

可另制作 DMG 并将其 SHA256 追加到校验文件。旧 GitHub Actions 流程依赖单独配置的证书和更新私钥，不代表本机新签名已自动迁移到 CI；当前以个人 Mac 的本地准备流程为准，不上传个人私钥来套用旧流程。

## 发布顺序

1. 确认目标版本与构建号未使用，提交发行源代码，创建对应版本的 GitHub Release 草稿。
2. 上传准备好的原始签名 ZIP、校验文件、DMG 与 appcast，核对文件名和下载地址。
3. 发布 Release，确认更新 ZIP 确实可下载并与本地哈希一致。
4. 将本次生成的 `appcast.xml` 放到 `updater/appcast.xml`，提交并推送到 `main`。更新列表必须晚于包可下载，不能先广播不存在的文件。
5. 后续版本使用真实旧版完成检查、下载、安装与重启，核对偏好和必要系统权限。

不要替换已经发布的同版本 ZIP。修复后必须递增版本与构建号；必要时可用原始已发布 ZIP 恢复其签名和列表，不能重新打包后覆盖。

## 验证

```sh
python3 -m unittest discover -s .github/scripts/tests
python3 Tests/check-architecture.py
AIRISLAND_UPDATE_FRAMEWORKS="$PWD/build/releases/2.8.19/DerivedData/Build/Products/Release" \
  bash Tests/run-software-update-tests.sh
```

同时设置 `AIRISLAND_UPDATE_PACKAGE_DIR` 为准备结果目录、`AIRISLAND_SPARKLE_BIN` 为工具目录，可验证真实 ZIP 签名并确认篡改副本被拒绝。准备工具检查错误配置、非本仓库下载地址、旧构建号、版本/长度/签名字段不一致等行为；生产更新策略测试确认手动检查允许、后台检查拒绝。

模型、签名与包检查不等同于真实升级验收。仍需覆盖无更新、网络断开、取消或损坏包、安装服务启动、重启、偏好保留、不同权限、安装路径与 macOS 版本。
