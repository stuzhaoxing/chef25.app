# iOS 原版 SillyTavern 运行时验证

## 结论

原版 SillyTavern 服务端可以作为一个内嵌的 Node.js 进程运行在 iOS App 中，再由
`WKWebView` 加载 `127.0.0.1` 上的原版页面。2026-11-04 已在 iPhone 真机完成安装、启动、
页面、Custom API 流式请求、聊天落盘、进程重启恢复和短时前后台恢复验证。

这是一份可行性结果，不是可发布客户端结论。当前 App 仍打包了完整 SillyTavern
`node_modules`，未评估长期后台、App Store 审核、签名分发、全部插件和全部模型供应商。

## 固定输入

- SillyTavern `1.19.0`
- SillyTavern commit `7e8663cd9c184a550b37238218bdd32c6efc68e9`
- Node.js `v24.5.0`
- nodejs-mobile v24 patchstack commit
  `5884aaa616c5268c66a64df6df4c2b00c475f687`
- App Bundle ID `com.chef25.mobile.node-spike`

官方 nodejs-mobile 最新正式发行版是 Node.js 18.20.4。SillyTavern 的
`package.json` 要求 Node.js 20 以上，而且 Android 实测证明缺少 Unicode 属性正则所需的
ICU 会让服务在启动时失败。因此本次没有把 Node.js 18 作为完成条件，而是使用
nodejs-mobile v24 patchstack 构建了实际 iOS runtime。

## 运行结构

`spike/ios-node-runtime` 是一个最小 UIKit 宿主：

1. 启动后先显示 25小厨移动端首页，不自动打开酒馆；
2. 用户点击「一键启动酒馆」后，在名为 `Chef25 Node.js` 的后台线程调用
   `NodeMobile.framework`；
3. 直接执行上游 `server.js`，监听 `127.0.0.1:8123`；
4. 轮询 `/version`，确认 SillyTavern `1.19.0`；
5. 用户点击「进入酒馆」后，在持久 `WKWebView` 加载原版页面，并把数据目录固定到
   App 私有容器。

首页复用 Desktop 的 ChefHat Logo、厨师帽吉祥物、品牌色、字号和
「我的酒馆 / 本地数据 / 中文文档 / 设置」导航，只保留两行欢迎文案、主操作和状态行。
进入酒馆后收起顶栏和底部导航，`WKWebView` 在顶部与底部系统安全区之间全屏显示，右侧
仅悬浮「‹ 小厨」返回入口；状态栏图标随浅色首页与深色酒馆自动切换，离开再回来不会
重新加载酒馆会话。数据页只展示并复制 App 私有目录，当前没有 Desktop 的 ZIP 导入导出、
重置和端口编辑。
`CHEF25_UI_TEST_MESSAGE` 存在时自动启动仅用于既有 UI 自动化。

上游 `server.js` 未改写。为了适配 nodejs-mobile 的 JIT-less V8，构建脚本替换了三个依赖
入口：

- `tiktoken` 改为不依赖 WebAssembly 的 tokenizer 实现；
- `@jimp/wasm-png` 和 `@jimp/wasm-jpeg` 改为 Jimp 的纯 JavaScript codec。

这些替换随打包副本生成，不修改固定版本的上游仓库。

## 真机结果

测试设备为 iPhone 15（`iPhone15,4`，iOS 27.0.1）。产品 App 使用开发签名安装并启动。

| 检查项 | 结果 |
| --- | --- |
| iOS arm64 Node framework | 构建成功，SHA-256 `caf20ebcce2e307a08c44c80357885edbeba2bcd9e028e718cbe941ab9803e49` |
| App 可执行文件 | SHA-256 `05d973dadef1edfffb9d8ea864216ff69c69fdea3beeeb5c42dcc12a8f757f29` |
| App 内 NodeMobile | SHA-256 `62035006907e9def36f2fc038a6469768d3a165660e6688d66cbc253c769b2dc` |
| 签名 | `codesign --verify --deep --strict` 通过 |
| 安装与启动 | `devicectl` 安装、启动成功 |
| 服务 | native Node.js `v24.5.0`，Webpack 编译成功，监听 `127.0.0.1:8123` |
| UI | SillyTavern `1.19.0` 原版页面正常加载和操作 |
| 网络请求 | Custom API `stream: true` 请求到达局域网假 SSE 服务 |
| UI 流式回复 | 原版页面显示完整回复，最终包记录 TTFT `193 ms` |
| 聊天文件 | 用户与助手消息均写入 JSONL，含 `api: "custom"`、模型和 TTFT |
| 进程重启 | 终止 App 后重新启动，聊天和完整消息恢复 |
| 短时前后台 | 切到 Settings 再回 App，原 PID 和完整聊天页面恢复 |

测试模型返回的固定文本是 `Native SillyTavern on iOS.`。这是测试 fixture 的内容，不代表
移动平台或模型能力。

## 证据

证据位于 `.build/evidence/`：

| 文件 | SHA-256 |
| --- | --- |
| `icon-preview-final.png` | `160757af7bccf648dd904dcb023ef8f8a6b93b042400d703342874e3baf168e6` |
| `ios-final-home.png` | `697887d357cdab1dc381aed1fbc3fa86211e1881678b3232b554e3beedf9a336` |
| `ios-final-page-loaded.png` | `64f0afa4dd903e02322eb2a7e572a86376bd5e430e4a6529086c73de3bbb75d7` |
| `ios-final-tavern-stream.png` | `43acbfc9664c0536bd9abd30681b9e9dbd7a2023237dc37646e5d2977249d0ea` |
| `ios-final-chat.jsonl` | `b7384cbffd480f8c82c4e1e17668fc6472ca17203585ec84f0f1c12bec2edc90` |
| `ios-final-last-request.json` | `36f20adcaae5d83c13e59a753de5f2e1197e1fc7958b4b8d63d4e5090d8823d8` |
| `ios-ui-home-final2-desktop-parity.png` | `d40b649d5a112156b7cebea6c3bdfb61823e2f5803c7b9f5a57fd05f57825650` |
| `ios-ui-tavern-stream-final.png` | `b5210f2bcf55ce511a3b2b7839ae2b8ce6340354b76ff52985bef09ae5e3bf05` |
| `ios-ui-tavern-chat-final.jsonl` | `0fccfd8f64b78d228f199895c9277c44d7ee2e940ae4d2267ee883a698ed7165` |
| `ios-ui-tavern-last-request-final.json` | `53cba474152e434af6b10212095168ed586923ea8db5ff6eb9b4129d6ad4c8d5` |
| `ios-shell-home.png` | `a0a67bd69f659bf64c1d3336c7451f816eacf4118e8484f4393cdd7f95ec12d8` |
| `ios-shell-tavern-reply.png` | `9ebd2c87457570ade5d45cdde19b3898a10a3cb6b60a14045a3fd63bf543dcdd` |
| `ios-shell-final-chat.jsonl` | `18c2d3afd0a2a8473b135c3ac26e883011734622a7d2b3b10ea7b9612a4a2952` |
| `ios-device-node24-stream-ui.png` | `58bde179e570b7667664e5ff1655139cd9e189d374d1979ca20c387b23801fa0` |
| `ios-device-node24-chat.jsonl` | `ad9e63b104dc23e2b9e6d8b0b3744c1d7511245f0e89102a6d445ccea08cc2bd` |
| `ios-device-node24-after-restart.png` | `6ca455105c77abd06104a0ef082f59d369d3a8df7cdcf83968151861b1b79373` |
| `ios-device-node24-foreground-recovery.png` | `4fd7a3cbd4b75d3144e0e34bd8fdb68c08c6d5e3fc243a37b1095a1ebac03245` |

本轮 iPhone 15 真机证据验证新版首页、酒馆全屏、Custom API 流式回复和 JSONL 落盘。
最终包测试消息为 `iOS-StatusBar-Final-20261104`，模型为 `chef25-local-fake`；酒馆截图
中只保留右侧「‹ 小厨」入口。覆盖安装后的数据目录仍包含上一轮
`iOS-UI-Desktop-Parity-20261104B` 和 `iOS-Icon-Final-20261104` 消息。

`ios-device-node24-page-loaded.png` 与
`ios-device-node24-foreground-after-install.png` 中的黑色画面是截图时机问题，不作为 UI
通过证据。

## 重建与安装

iOS Node framework 由 patchstack 构建，产物路径为：

```text
<node24-patchstack>/out_ios_arm64/iphoneos-arm64/Release-iphoneos/NodeMobile.framework
```

使用开发签名重建宿主：

```sh
./spike/assets/generate-icons.sh
ST_SOURCE=/path/to/SillyTavern \
NODE_MOBILE_FRAMEWORK=/path/to/NodeMobile.framework \
IOS_TARGET=device \
OUT_DIR=/path/to/output \
SIGNING_IDENTITY="$IOS_SIGNING_IDENTITY" \
PROVISIONING_PROFILE=/path/to/profile.mobileprovision \
./spike/ios-node-runtime/build-simulator.sh
```

安装、启动和日志：

```sh
xcrun devicectl device install app --device "$IOS_CORE_DEVICE_ID" \
  /path/to/output/Chef25NodeSpike.app
xcrun devicectl device process launch --device "$IOS_CORE_DEVICE_ID" \
  --terminate-existing --console com.chef25.mobile.node-spike
```

`CHEF25_UI_TEST_MESSAGE`、`CHEF25_UI_TEST_API_URL` 和
`CHEF25_UI_TEST_MODEL` 可自动驱动一次 UI 发送；iOS 使用进程环境变量传入。

## 未证明边界

- 没有证明 App 在长期后台、锁屏或系统内存压力下持续运行；iOS 正常会暂停应用。
- 没有完成 App Store / TestFlight 分发、生产证书、隐私清单和审核验证。
- 没有逐一验证 SillyTavern 的所有扩展、插件、供应商 API、文件导入和媒体处理。
- 没有证明依赖 `child_process` 或完整 WebAssembly/JIT 的服务端功能可运行。
- 当前 577 MiB 的 App 包仍是可行性 harness，不能直接作为产品体积或架构结论。
