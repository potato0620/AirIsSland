# 应用内更新与独立发行

关于页和菜单栏的“检查更新…”使用同一个 Sparkle 更新器，在独立窗口内检查版本、展示说明、下载并在确认后安装重启。首次点击才启动更新器，只允许手动检查，不增加自动下载、更新渠道或岛内进度设置。

首次安装仍从 GitHub Release 下载 DMG 或 ZIP。2.8.9 及更早版本没有更新入口，需要手动安装一次带更新器的版本；之后才可以应用内升级。应用应放在“应用程序”等可写的本机目录，从只读 DMG 直接运行时不能原地更新。Sparkle 在必要时处理安装位置授权。

## 更新源与签名

- 更新列表：`https://raw.githubusercontent.com/potato0620/AirIsSland/main/updater/appcast.xml`。
- 下载包：本仓库 GitHub Release 中的 `AirIsland-版本-macOS-arm64.zip`。DMG 可继续作为手动安装入口。
- `Info.plist` 保存公开的 `SUPublicEDKey`，下载包在解压前用 Ed25519 验签。SHA256 文件用于手动核对，不能代替签名。
- 私钥保存在 macOS 登录钥匙串的 Sparkle `AirIsland` 账户，不在仓库中。使用 Sparkle 的 `generate_keys --account AirIsland -p` 可读取公钥；不要为每次发布重新生成密钥。请通过安全方式备份钥匙串中的私钥。
- 原有 bundle ID、偏好与用户数据路径保持兼容。本地签名与 Sparkle 更新签名承担不同职责；更新器不等于 Apple Developer ID 签名或公证。

更新列表只包含 AirIsland 已正式发布的稳定版本，不能加入上游应用的历史版本或未发布的测试包。新条目必须在对应安装包发布且可以下载后上线。后台检查偏好即使从旧版保留下来，也不能绕过手动检查策略。

## 本地构建与准备

### 本机开发更新的固定签名

`CODE_SIGN_IDENTITY=-` 属于无证书的 ad-hoc 签名，默认指定要求使用本次代码哈希。代码更新后哈希变化，系统保存的隐私授权可能不再匹配。重复弹窗应修复签名身份，不能用清空 TCC、篡改权限记录或关闭系统保护来处理。

没有 Apple Developer 账号时，本机开发可使用固定自签名代码证书。首次初始化：

```sh
python3 Configuration/signing/local_signing.py init
```

私钥导入当前用户默认钥匙串，只有 `/usr/bin/codesign` 获准使用；临时私钥和 PKCS#12 文件随临时目录清理。公有证书与身份配置位于 `~/Library/Application Support/AirIsland/LocalSigning`，不进入仓库。工具不安装受信任根证书，不修改 TCC、Gatekeeper 或系统信任设置。请通过钥匙串的安全备份保留此身份；丢失私钥时必须恢复原身份，工具不会自动重新生成。

以后本机安装验证统一使用：

```sh
bash Configuration/signing/build-local.sh
```

默认产物在 `build/local-signed/DerivedData/Build/Products/Release/AirIsland.app`。可用 `AIRISLAND_LOCAL_DERIVED_DATA` 指定既有构建目录、`AIRISLAND_SOURCE_PACKAGES` 复用已解析的包缓存。脚本先完成 Release 构建，再从内到外给 AirIslandHelper 和主应用签名，保留各自 bundle ID、权限声明与原标志。最终指定要求同时固定 bundle ID 和证书指纹，不使用只有名称的宽松要求；证书/私钥缺失时失败，不回退 ad-hoc。确认最终签名校验通过后退出旧版再替换，不能安装中间产物。

从旧 ad-hoc 身份切换到此身份，第一次仍需重新同意相应权限。后续构建保持相同签名要求，可在升级前后双向验证身份；音频采集与提醒事项的实际授权是否保留仍需分别做系统升级实测，不能只凭签名测试宣称已完成。此方式用于本机开发，不是 Apple Developer ID 或公证，**不要将本机自签名产物用于正式公开发行**。公开版本应使用同一开发者团队的 Developer ID 身份，并验证跨版本指定要求兼容。参见 Apple [签名要求](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)与[代码签名任务](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html)。

### 当前公开发行包的准备方式

在尚无 Developer ID 证书时，当前公开渠道继续使用以下 ad-hoc 构建方式，而非本机自签名身份。此渠道未公证，代码更新后系统权限仍可能需要重新同意；发布说明必须明确这一限制，不能宣称公开包已解决跨更新授权保留。

当前内置 MediaRemoteAdapter.framework 的 Mach-O 最低系统为 15.0，主应用、辅助进程和发布说明统一要求 macOS 15 及以上。使用新 Xcode/SDK 不等于只能在同版本系统运行；发布前还需核对各嵌套二进制的实际最低系统，不能只读取主应用的 Info.plist。最低目标检查不等于旧系统真机验收。

先同步 `main` 与最新已发布更新列表，再按发布目标递增工程中主应用与辅助服务的版本、构建号，运行相关回归测试，再完整构建 Release。构建号必须大于更新列表中所有已发布条目；营销版本使用稳定的 `major.minor.patch`。禁止用更改版本号后的未重新签名副本发布。

以下是当前 Apple Silicon、本地签名发行方式的构建示例。关闭 Hardened Runtime 是这条本地签名构建命令的参数，避免对没有 Developer ID 的应用启用 Library Validation；不修改工程中正式签名的默认配置。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project AirIsland.xcodeproj -scheme AirIsland -configuration Release \
  -derivedDataPath build/updates/DerivedData \
  build CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
```

Sparkle 工具在 Xcode 包缓存的 `SourcePackages/artifacts/sparkle/Sparkle/bin` 中，与 `Package.resolved` 锁定版本一致。用实际目录替换下例的工具路径，准备真实版本说明文件：

```sh
python3 .github/scripts/prepare_update.py \
  --app build/updates/DerivedData/Build/Products/Release/AirIsland.app \
  --sparkle-bin build/updates/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin \
  --notes /absolute/path/to/release-notes.txt \
  --output build/updates/prepared-release
```

工具只接受新的输出目录。它校验 bundle ID、更新地址、公钥、手动更新配置、递增构建号、嵌套代码签名和 arm64 架构；从钥匙串确认签名账户，使用 `ditto` 保留应用结构，调用官方 `generate_appcast` 生成嵌入说明的列表，再使用 `sign_update` 校验真实 ZIP。输出 ZIP、`SHA256SUMS.txt`、`appcast.xml`，不会导出私钥、改写源列表或发布任何内容。

若并行维护其他发布渠道，先将各渠道已发布的最高构建号合并考虑。此本地工具只生成一个稳定版条目；旧 GitHub Actions 工作流仍依赖证书及其发布密钥配置，不能视为已经启用的自动发布链路。

## 发布顺序

1. 确认目标版本与构建号未使用，创建对应 `v版本` 的 GitHub Release 草稿。
2. 上传准备好的 ZIP、校验文件，以及需要提供的 DMG；确认文件名与列表中的下载地址完全一致。
3. 发布 Release，确认列表中的 ZIP 地址已能下载。
4. 将本次生成的 `appcast.xml` 放到 `updater/appcast.xml`，提交并推送到 `main`。列表更新必须晚于更新包可下载，不能先广播不存在的文件。
5. 使用真实旧版检查到该版本，完成一次下载、安装与重启，并核对偏好和必要系统权限。

准备包、发布 Release、推送更新列表是不同操作。对同一个已发布版本不要替换 ZIP；修复后重新递增版本和构建号。

原更新签名私钥暂不可用时，可先发布手动安装的 ZIP、DMG 和校验文件，在发布说明中标明应用内更新暂未开放，并保留现有有效的更新列表。不得重新生成密钥或更换公钥绕过旧版本验签。原密钥恢复后，以已经发布的原始 ZIP 生成签名和更新列表，再验证包哈希及签名后补发列表；不要重新打包或替换同一版本的 ZIP。2.8.18 当前按此手动发布流程交付，更新列表暂保留 2.8.17。

## 验证

```sh
python3 -m unittest discover -s .github/scripts/tests
python3 Tests/check-architecture.py
AIRISLAND_UPDATE_FRAMEWORKS="$PWD/build/updates/DerivedData/Build/Products/Release" \
  bash Tests/run-software-update-tests.sh
```

可同时设置 `AIRISLAND_UPDATE_PACKAGE_DIR` 为准备结果目录、`AIRISLAND_SPARKLE_BIN` 为工具目录，验证真实更新包签名并确认篡改后的副本被拒绝。准备工具的单元测试检查配置不匹配、上游更新源、旧构建号、版本/下载地址/长度/签名字段不一致等拒绝行为；Swift 测试调用生产更新策略，确认手动检查允许、后台检查拒绝。

模型与签名检查不能替代真实安装。另需覆盖无更新、网络断开、下载取消、损坏包、安装服务启动、安装重启、偏好保留、不同权限与安装路径。当前本地签名发行包未经 Apple 公证，需单独验证系统安全检查与辅助功能等权限在升级后的行为。
