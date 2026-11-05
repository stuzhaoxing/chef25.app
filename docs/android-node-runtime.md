# Android 原版 SillyTavern 运行时验证

## 结论

原版 SillyTavern 服务端可以编译进 Android App，在 App 进程内启动 Node.js，由
`WebView` 加载 `127.0.0.1:8123` 上的原版 UI。当前发布流水线固定 Node.js `24.22.1`
和 SillyTavern `1.19.0`。2026-11-05 已在 Android 16 KB page size arm64 模拟器完成
签名发布包、Custom API 流式回复、聊天落盘、Activity 重建、进程重启和 30 秒后台恢复验证。

App 现在先显示 25小厨移动端首页，点击「一键启动酒馆」后才启动运行时；运行就绪后再由
「进入酒馆」打开原版页面。外壳复用 Desktop 的 ChefHat Logo、厨师帽吉祥物、品牌色、
字号、圆角和以下导航：

- 「我的酒馆」：启动、进入，以及进入后的「返回小厨」；
- 「本地数据」：显示并复制 App 私有数据目录；
- 「中文文档」：加载 `chef25.com` 的中文使用指南；
- 「设置」：显示回环地址、Node.js、SillyTavern 和运行状态。

进入酒馆后 25小厨顶栏和底部导航收起，`WebView` 占据系统安全区之间的可用空间，右侧
仅保留「‹ 小厨」返回入口。返回首页再进入时复用同一实例和页面状态。Desktop 的端口
编辑、ZIP 导入导出、重置和更新功能尚未移植。测试 Intent 含
`CHEF25_UI_TEST_MESSAGE` 时自动启动，便于既有 UI 自动化，不影响普通启动流程。

当前是可发布的开发预览。Android 发布包使用独立密钥签名，Node 服务仍与
`Activity` 同进程；尚无独立前台服务、应用商店分发或长期后台保障。

## 0.1.2 lifecycle repair

0.1.1 在关闭 `Activity`、保留进程后重新打开页面时，会尝试在同一进程中第二次调用
`node::Start`，最终触发 `SIGABRT`。0.1.2 将 Node runtime 的可恢复状态保存在进程级
单例中，并让重建后的 `Activity` 重新连接已运行的实例，而不是再次启动 Node。

0.1.2 debug 包在 `versionCode=12`、Android 16 arm64 16 KB page size 模拟器上验证：

- Activity 关闭后 PID 保持为 `7508`，WARM 重启后仍为同一 PID；
- 日志中没有第二次 `node::Start`、`SIGABRT` 或 `FATAL EXCEPTION`；
- 重新进入后恢复此前写入的 JSONL 聊天；
- Custom API 收到包含真实用户消息、模型 `chef25-local-fake` 和 `stream: true` 的请求；
- 页面收到并渲染 SSE 助手回复；
- Home 切后台 30 秒后 PID 不变，回到前台恢复同一聊天；
- 酒馆 `WebView` 使用 `[0,132][1080,2337]`，仅额外保留「‹ 小厨」返回入口。

## 固定输入

- SillyTavern `1.19.0`
- SillyTavern commit `7e8663cd9c184a550b37238218bdd32c6efc68e9`
- Node.js `v24.5.0`
- nodejs-mobile v24 patchstack commit
  `5884aaa616c5268c66a64df6df4c2b00c475f687`
- Android 16，`arm64-v8a`，AVD `gpt123_test`，序列号 `emulator-5554`
- App ID `com.chef25.mobile.nodespike`

## Node.js 24 构建修复

第一次 Android 启动没有 ICU。页面尚未完成初始化时，Node 进程即因以下语法错误退出：

```text
SyntaxError: Invalid regular expression:
/^\p{Cc}|\p{Cf}|\p{Co}|\p{Cs}$/u: Invalid property name
```

修复后的 Android configure 使用 small ICU：

```text
--with-intl=small-icu --with-icu-locales=root,en
```

生成的配置确认：

```text
v8_enable_i18n_support: 1
icu_small: true
icu_locales: en,root
```

构建过程中还包含以下 Android 适配：

- 修正 JNI local reference 生命周期，避免启动阶段崩溃；
- 将 `-latomic` 的链接范围限定到正确 toolset；
- 使用 Android target flavor；
- Node stdout/stderr 写入 App 私有文件 `files/node-output.log`；
- Node runtime 是 Android 进程内的单例。Activity 被重建或从首页重新打开时复用原来的
  `node::Start` 实例，避免第二次启动同一个进程内的 Node.js 而触发原生退出；
- 构建后由 `scripts/verify-apk-16kb.sh` 强制检查 APK 内所有 ARM64 ELF 的
  `PT_LOAD` 至少为 `0x4000` 对齐，以支持 16 KB page size。

## 产物

未 strip 的 Android Node 库：

```text
/tmp/chef25-node24-android-build/out/Release/libnode.so
SHA-256 2098e27fc40cb4ae275a798e31869dd8748c67c9886fa125f71cff18dc9ee73f
ELF64 AArch64
```

当前 debug APK：

```text
spike/android-node-runtime/app/build/outputs/apk/debug/app-debug.apk
253,594,033 bytes
SHA-256 2f0c1a80a5fae2c656983c54a2f9ee7ed1727bc549ab1ed2977597d9d4c28c8d
```

APK 内 strip 后的 `lib/arm64-v8a/libnode.so` SHA-256 为
`83dab5bb973cca8f06eb2a5f39a51f49403a42ef64dbfc97701b8d35f038dd10`。

## 实测结果

| 检查项 | 结果 |
| --- | --- |
| APK 构建 | Gradle `assembleDebug` 成功 |
| 覆盖安装 | `adb install -r` 成功，未清 App 数据 |
| Node runtime | native Node.js `v24.5.0` 启动成功，越过 Unicode 正则错误 |
| SillyTavern | Webpack 编译成功，监听 IPv4 `127.0.0.1:8123` |
| UI | SillyTavern `1.19.0` 原版页面正常加载 |
| API 自动化 | 操作原版控件切换到 Custom，并断言 URL 和 source 生效 |
| 页面发送 | 自动化调用原版页面的发送按钮，不修改 `displayNone` 或页面样式 |
| 流式请求 | 假 SSE 服务收到 `stream: true`，消息和模型正确 |
| UI 回复 | 页面实际显示完整助手消息 |
| 聊天文件 | JSONL 写入 `Android-UI-Desktop-Parity-20261104` 和助手回复，含 `api: "custom"`、模型和 TTFT `164 ms` |
| 页面返回 | 点击「小厨」回首页，同 PID 再次进入后原聊天消息仍在 |
| 进程重启 | `am force-stop` 后 PID 改变，重新打开同一聊天可见完整两轮消息 |
| 30 秒后台 | 前后 PID 均为 `7036`，回环监听保持，回前台聊天完整 |

假 SSE 的固定回复文本是 `Native SillyTavern on iOS.`。这是测试 fixture 中沿用的文本，
Android 结果记录的是实际返回内容，不应据此推断平台能力。

## 证据

最终自动化测试证据位于 `.build/evidence/`：

| 文件 | SHA-256 |
| --- | --- |
| `icon-preview-final.png` | `160757af7bccf648dd904dcb023ef8f8a6b93b042400d703342874e3baf168e6` |
| `android-icons-final-app-drawer.png` | `a4ed6a6376d7d8b26fce7d006d4d4df444d45ce1f1e2685346336f3923a48ce4` |
| `android-icons-final-app-home.png` | `3adb98d692fb14f4440b6301fc17adf4b904def8e25aa3de96492fbd1cee0189` |
| `android-icons-final-tavern-fullscreen.png` | `6a0422f6724df02676460c0a4687b8cdad4feefadbec75e4c1dd9e0a5fe3b0cd` |
| `android-ui-home-final-desktop-parity.png` | `3e13a8456d273dd69fb1d094429da9d1106ae1ad2f459f22843fd26de9aa72f4` |
| `android-ui-data-final.png` | `ee7e4429c4040f13d1968ced4ec86a656be7e50c3ccb919d2882e05d50b13e7d` |
| `android-ui-docs-final.png` | `0afa994a705976340007fe24a6033ee6bea45882c3b943ac09966f93b32429bc` |
| `android-ui-settings-final.png` | `5ba2d6fd3b8e42c1ffea8d3fdb8eb36de68a08c241be26b41b97f213e393ecaf` |
| `android-ui-tavern-stream-final.png` | `f3728b15984819d2948c90469de97b129c8f6eeddbbdc9be497a553ea654d313` |
| `android-ui-tavern-chat-final.jsonl` | `24d9a698abcb4e224aea8d59ec46e713eb29e2d0a18a407fba8ade1c2c911a23` |
| `android-ui-tavern-last-request-final.json` | `edc12eb538655aab39d84821c90a360802703367ea02bf601a8df9c87a59cb75` |
| `android-ui-session-restored-final.png` | `4b88500e8fbce1dffd34c72079ca182fd863bb4aa54ad6c367656625ce678764` |
| `android-shell-home-final3.png` | `e8bdee0062dcb9d08f25631b91f99618205ea69e53cbb12411c84f3b80b66cc1` |
| `android-shell-click-started.png` | `f9c1184aaa3b92851c9f067f9bbda770937092e26cb0cfc9e2278847a1d9f93d` |
| `android-shell-click-entered-tavern.png` | `bfce16ae5c88802a9082e0350ee392b91e9df8ad23649c881186a9029ea0cc68` |
| `android-shell-data.png` | `fdf929d9e75fea9ba15c87716fd3aea02748732074fd3fbaac027ea49f045799` |
| `android-shell-docs.png` | `3bce5a7fcaa3961f3621b62c3c11c8b882fcd2f93c1f89b0be7ad564b9f132f9` |
| `android-shell-settings.png` | `9ba7e10d31c040fb8bd0cc90fe04f7dcf5deb12d8409a02b7c30734a6395f182` |
| `android-shell-tavern-shell-final.png` | `feec48d3bab1b4b8878208742baaf59954930da2b7409cf0508d1151b7387fbf` |
| `android-shell-tavern-reply-final.png` | `db99f2511e8d58a15d6cea1fecd47ff2f5aa896d5e47f31e1b0cdc80e7895daa` |
| `android-shell-final-chat.jsonl` | `bbd5e6ee7aac0d730bb1524844e3d7c128ffe91d78441fd40ff40fe8b7500981` |
| `android-shell-final-last-request.json` | `43ba379fcd3767be41a1f0d866d21f5f6f800f270736238915dbf2a7f6d97643` |
| `android-shell-final-node-output.log` | `5b7c8fc0682891ba6763dcf88dba0c7d6f825746f026d1bd39a2537133c4de35` |
| `android-device-node24-icu-auto-api-stream-ui.png` | `a41bdfbd31771b5ccd74b3ff1a0c8212c371f73bf00586d79c9833a3d78ed0ff` |
| `android-device-node24-icu-auto-api-chat.jsonl` | `48ef06bb5748a20ca1067112ce107b5f5b7f77fe904ecb84a1af0fd948814c44` |
| `android-device-node24-icu-auto-api-last-request.json` | `b9935814bb4e916a8e76b27f159826fac9dccf69d743fc6cb6d4074a9b0ee455` |
| `android-device-node24-icu-auto-api-node-output.log` | `c903a7893899e57004ccadb1751c26c125ad0ff0bfbbdc1bf1cce4f8b9c05377` |
| `android-device-node24-icu-auto-api-after-restart-chat.png` | `05d35c8d5e556534472bc2191e0eabd4c355f0273549914fc7a25fd2294baf63` |
| `android-device-node24-icu-auto-api-after-30s-background.png` | `e46f67e8287a43e92e76a2a1c44dedcda1b0a50511136bdd6bf6bef21468fa48` |

早期手工配置版证据仍保留为
`android-device-node24-icu-stream-ui.png`、`android-device-node24-icu-chat.jsonl`
等文件；最终结论以 `auto-api` 文件为准。

本轮截图包括新版首页、本地数据、中文文档、设置、酒馆流式回复和返回后的会话恢复。
Android 16 的状态栏和手势导航区按系统 Insets 留白；酒馆内没有额外的 25小厨栏占用，
安全区之外均交给原版页面。

## 重建

先按 nodejs-mobile patchstack 构建 Android arm64 Node 库。当前 harness 使用：

```sh
./spike/assets/generate-icons.sh
ST_SOURCE=/path/to/SillyTavern \
NODE_SOURCE=/path/to/node24-patchstack \
LIB_NODE=/path/to/node24-patchstack/out/Release/libnode.so \
GRADLE_BIN=/path/to/gradle-9.3.1/bin/gradle \
./build-apk.sh
```

安装和 UI 自动测试：

```sh
adb -s emulator-5554 install -r \
  app/build/outputs/apk/debug/app-debug.apk
adb -s emulator-5554 shell am start \
  -n com.chef25.mobile.nodespike/.MainActivity \
  --es CHEF25_UI_TEST_MESSAGE 'Android-Auto-API-SSE-20261104' \
  --es CHEF25_UI_TEST_API_URL 'http://10.0.2.2:8124/v1' \
  --es CHEF25_UI_TEST_MODEL 'chef25-local-fake'
```

Node 输出位于：

```sh
adb -s emulator-5554 shell run-as com.chef25.mobile.nodespike \
  cat files/node-output.log
```

## 未证明边界

- 没有在物理 Android 手机、低内存设备或不同厂商 ROM 上安装运行。
- 30 秒 Home 切后台通过不能证明长期后台、Doze、系统回收或息屏后持续服务。
- 当前没有 Android foreground service、notification、wake lock 或后台保活策略。
- 当前没有 App Bundle、Play Store 或实体 Android 设备验收；16 KB 构建已在本机
  Android 16 Page Size 16 KB 模拟器安装，并以最终产物继续复验。
- 没有验证 x86_64、32 位 ARM 或非 arm64 ABI。
- 没有逐一验证 SillyTavern 的全部扩展、插件、供应商 API、媒体处理和 WebAssembly 功能。
- 当前 253,594,033 字节的 APK 只是内嵌完整运行时和依赖的可行性产物，不能直接视为产品包设计。
