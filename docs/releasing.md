# Mobile 构建与发布

## 流程

`.github/workflows/ci.yml` 在 pull request、main 推送和人工触发时检查配置，并在
Ubuntu/macOS runner 中构建 Android debug APK 与 iOS Simulator App。
配置检查同时运行 Mobile R2 发布器的容量、不可变对象、清单和故障恢复测试。

`.github/workflows/release.yml` 只允许在 `main` 人工触发，默认 `publish=false`、
`testflight_only=false`：

1. 校验 `mobile-version.json`、`runtime.lock.json` 和本机发布脚本；
2. 从固定 GitHub Release 下载 Node.js Mobile `24.22.1-0`，核对 SHA-256；
3. 从固定 commit 获取 SillyTavern `1.19.0`，安装生产依赖并应用 mobile runtime 适配；
   打包时移除非运行时需要的 `node_modules/.bin` 链接，避免 App Store 因 bundle 内
   symbolic link 拒绝 IPA；
4. 用 macOS 26 runner 上的 Xcode 26+ / iOS 26+ SDK 生成 iOS 工程，归档兼容
   TestFlight 的 App；工具链低于 iOS 26 SDK 时在归档前停止；
5. 构建并验证 Android release APK、APK v2 签名、SHA-256 和 16 KB 对齐；
6. 勾选 `testflight_only` 时仅签名 iPhone 构建并上传 TestFlight，不要求公开链接或 R2；
7. 勾选 `publish` 时上传 iPhone 构建到 TestFlight，把 Android APK、完整清单、
   SHA256SUMS 和对应源码归档发布到 R2；
8. 从公网重新读取并校验清单、长度、SHA-256 和 Range，再创建 GitHub Pre-release。

Node 运行时锁在 `runtime.lock.json`。不要提交下载包、解压目录、
`spike/android-node-runtime/libnode/`、assets 中的运行时 ZIP 或签名文件；这些都已在
`.gitignore` 中排除。

## 版本

`mobile-version.json` 是用户可见版本号唯一来源，`package.json` 必须保持相同版本。
TestFlight 和 Android 的 build number 使用 GitHub run number，因此同一仓库内单调递增。
已发布到 R2 的版本目录不可覆盖；再次发布必须提高版本。

Mobile 与 Desktop 共用 `chef25-downloads` bucket。发布器在持有 Mobile 独立锁后分页
统计整个 bucket，超过 9 GB、10,000 个对象或存在未完成 multipart upload 时拒绝发布。
它不会读取、覆盖或释放 Desktop 的 `downloads/latest.json`、
`downloads/updater.json` 和 `downloads/.publish-lock`。

## GitHub 环境

在 Mobile 仓库创建 Environment `mobile-release` 并限制为 `main`。Variables：

| 名称 | 示例 |
| --- | --- |
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `TESTFLIGHT_PUBLIC_URL` | `https://testflight.apple.com/join/<code>` |
| `CLOUDFLARE_ACCOUNT_ID` | R2 所在 Cloudflare 账户 ID |
| `CHEF25_R2_BUCKET` | `chef25-downloads` |
| `CHEF25_DOWNLOAD_ORIGIN` | `https://download.chef25.com` |

Secrets：

| 名称 | 内容 |
| --- | --- |
| `APPLE_DISTRIBUTION_CERTIFICATE_BASE64` | Apple Distribution `.p12` 的 base64 |
| `APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD` | `.p12` 密码 |
| `APPLE_PROVISIONING_PROFILE_BASE64` | `com.chef25.mobile.node-spike` 的 App Store Distribution profile |
| `APP_STORE_CONNECT_KEY_ID` | App Store Connect API Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | API Issuer ID |
| `APP_STORE_CONNECT_PRIVATE_KEY_BASE64` | `AuthKey_<id>.p8` 的 base64 |
| `ANDROID_KEYSTORE_BASE64` | Android release `.jks` 的 base64 |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore 密码 |
| `ANDROID_KEY_ALIAS` | Release key alias |
| `ANDROID_KEY_PASSWORD` | Release key 密码 |
| `R2_ACCESS_KEY_ID` | 仅限 `chef25-downloads` 的 R2 S3 Access Key ID |
| `R2_SECRET_ACCESS_KEY` | 对应 Secret Access Key |

API Key 需要可管理 App ID、证书、Provisioning Profile 和 TestFlight 的权限。
App Store Connect 中必须已有 Bundle ID `com.chef25.mobile.node-spike` 和 App 记录，
归档使用 profile `Chef25 Mobile App Store` 和显式 `Apple Distribution` 身份；工作流会
校验 profile 对应上述 Bundle ID、不是 development profile，并在导出前拒绝仍含
`Apple Development` 签名的 archive。签名 profile 到期或 Apple Distribution 证书
重建后，需要同步更新 GitHub Environment 中的 profile 和证书 Secret。

## TestFlight 公开链接

Action 能自动上传构建，但公开链接仍取决于 Apple 侧状态。首次需要：

1. 首次构建先人工触发 `testflight_only=true`；
2. 在 App Store Connect 启用 External Testing；
3. 创建或选择对外测试组；
4. 等待 Apple 完成该构建的 Beta App Review；
5. 启用 Public Link，把完整链接写入 `TESTFLIGHT_PUBLIC_URL`。

清单和官网只接受真实的 `https://testflight.apple.com/join/<code>`。TestFlight-only
上传不要求该变量；完整 `publish=true` 在缺少链接时会在构建开始前失败。工作流不会
伪造链接或绕过审核。

## R2 路径

Mobile 使用与 Desktop 分开的命名空间：

```text
downloads/mobile/v<version>/distribution.json
downloads/mobile/v<version>/SHA256SUMS
downloads/mobile/v<version>/Chef25_<version>_android-arm64.apk
downloads/mobile/v<version>/Chef25_<version>_source.tar.gz
downloads/mobile/latest.json
```

发布器使用独立锁 `downloads/mobile/.publish-lock`，不会修改 Desktop 的
`downloads/latest.json` 或更新器清单。发布失败时先确认没有其他 Mobile 发布任务，
再人工处理这个锁；不要按时间自动清理。

`download.chef25.com` 的 Pages Function 必须先部署支持
`downloads/mobile/latest.json` 和 `downloads/mobile/v<version>/` 的版本。Mobile 工作流
只上传并验证 R2 对象与清单，不负责部署这个位于 Desktop 仓库的下载网关；网关未更新时，
首次公开验证会以 404 失败且不会激活清单。

## 首次发布验收

1. 先运行 `publish=false`，确认 iOS unsigned archive 与 Android debug APK 均构建成功；
2. 配好 Environment 后在 App Store Connect 创建 App；
3. 运行 `testflight_only=true`，等待 TestFlight 处理完成并完成公开测试配置；
4. 把 Public Link 写入 `TESTFLIGHT_PUBLIC_URL`；
5. 运行 `publish=true`，确认 External Beta Review 状态符合预期；
6. 确认 R2 公网 manifest 禁用缓存、Android APK 长度/SHA-256/Range 正确；
7. 部署官网，访问 `/api/downloads/mobile.json`，从官网下载 APK 并在 Android arm64 真机安装；
8. 在 iPhone 通过 TestFlight 公开链接安装新构建，复验启动、流式回复、重启恢复和覆盖升级；
9. 配置 CDN 后核对国内网络下的下载稳定性。云端上传成功不等于真机验收通过。
