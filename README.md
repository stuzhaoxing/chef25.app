# 25小厨 · Mobile

手机客户端仓库。iOS 和 Android 客户端都在 App 内运行原版 SillyTavern，
并由 GitHub Actions 构建；发布链路把 Android APK 放到 Cloudflare R2，把 iOS
构建上传 TestFlight，再由官网提供 Android 下载和 TestFlight 公开入口。

两个平台现在先打开 25小厨移动端首页，不再启动即进入酒馆。首页沿用 Desktop
的品牌色、启动状态、主操作和「我的酒馆 / 本地数据 / 中文文档 / 设置」导航；点击
「一键启动酒馆」后才启动内嵌运行时。进入原版 SillyTavern 后收起 25小厨顶栏和
底部导航，只保留右侧「‹ 小厨」返回入口，把系统安全区之间的空间交给酒馆。

两个 spike 都直接运行原版 SillyTavern `server.js`，没有迁移 Desktop，也没有重写 Node
后端：

- [iOS Node runtime](spike/ios-node-runtime/README.md)：Node.js 24.5.0 已在 iPhone
  15 真机完成 UI、Custom API 流式回复、聊天持久化和短时前后台恢复；见
  [iOS 可行性记录](docs/ios-node-runtime.md)。
- [Android Node runtime](spike/android-node-runtime/README.md)：Node.js 24.5.0 已在
  Android 16 arm64 模拟器完成 UI、Custom API 流式回复、聊天持久化和 30 秒前后台恢复；
  见 [Android 可行性记录](docs/android-node-runtime.md)。

发布流水线升级并锁定 Node.js `24.22.1` mobile runtime。它承接上一轮 Node.js
`24.5.0` 的可行性结果，但仍需在合并前通过新的 GitHub Actions 和真机复验。

当前移动外壳提供精简启动页、数据目录复制、中文文档和运行时信息。
Desktop 的端口编辑、ZIP 导入导出、数据重置和更新功能尚未移植到这个移动可行性版本。
两端 App 图标复用 Desktop 的橙底 ChefHat 标记，并分别提供 iOS 多倍率资源、Android
adaptive 图标和 API 24–25 的 legacy fallback；统一生成入口是
`spike/assets/generate-icons.sh`。
长期移动后台、实体 Android 设备、全部插件/供应商兼容和产品级包体优化仍未验证。
发布、签名、TestFlight 和 Cloudflare 配置见
[Mobile 发布流程](docs/releasing.md)。
