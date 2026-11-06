# 25小厨 · Mobile

手机客户端仓库。iOS 和 Android 客户端都在 App 内运行原版 SillyTavern，
并由 GitHub Actions 构建；发布链路把 Android APK 放到 Cloudflare R2，把 iOS
构建上传 TestFlight，再由官网提供 Android 下载和 TestFlight 公开入口。

移动端外壳使用小厨自定义 UI 组件，不使用系统默认外观的弹窗、按钮或输入框。
Android 的 `ChefDialog` / `ChefButton` / `ChefTextInput` 与 iOS 的
`ChefDialogController` / `ChefActionButton` / `ChefTextField` 统一提供米白面板、
橙色操作、描边输入框和禁用状态。重置确认、结果提示、路径复制反馈和关于页共用弹窗；
确认短语必须完全匹配，取消或返回不执行操作。弹窗内容可滚动，输入时适配键盘。

两个平台现在先打开 25小厨移动端首页，不再启动即进入酒馆。首页沿用 Desktop
的品牌色、启动状态、主操作和「我的酒馆 / 本地数据 / 中文文档 / 设置」导航；点击
「一键启动酒馆」后才启动内嵌运行时，就绪后自动进入酒馆，无需再次点击；若等待期间切换到其他页面，则不打断当前页面。首页只由主按钮显示启动状态，不再显示按钮下重复的小字。首页主内容在可用区域垂直居中，空间不足时可滚动。
导航通过左上角按钮或从左边缘右滑展开：侧栏随手指横向拖动，主页面向右推开并露出
圆角和阴影；侧栏宽度为屏宽的 82%，上限 380 pt/dp。左滑、点击露出的主页面、
选择页面菜单或 Android 返回键可收起。侧栏中部菜单可滚动，底部固定「关于」入口，
原右上角的信息按钮已移入此处，可查看版本信息；点击「关于」只打开弹窗，侧边栏保持
展开，关闭弹窗后仍保留展开状态。
进入原版 SillyTavern 后收起 25小厨顶栏和侧栏，只保留浅色「返回小厨」悬浮气泡（无箭头，常规尺寸约 76 × 30 pt/dp），
把系统安全区之间的空间交给酒馆；此时不捕获酒馆内的侧栏手势。
返回气泡可拖动，松手后以约 491 ms 的弹性动画吸附到最近的左右边缘，并保留当前高度；
位置限制在安全区域内，窗口尺寸改变时重新贴边。拖动不触发返回，普通点击返回首页；
系统关闭动画时直接贴边。动效参考 Next.js 开发指示器，改用左右边缘而非四角吸附。

首页吉祥物使用统一的 12 秒动作节奏：平视停留、侧向注视、回正、眨眼微笑，再放松。
视线先移动，头部延后 140 ms 同向跟随；普通眼和笑眼只在完全闭眼时切换，闭眼保留
清晰短线，嘴角和腮红随微笑联动。离开首页、展开侧栏或进入后台时暂停并保留当前
姿态；iOS 的「减少动态效果」和 Android 的系统动画关闭设置使用静态表情。
动作计算位于两端的 `MascotMotion`，可运行 `python3 tests/test_mascot_motion.py` 检查
跨平台一致性、跟随方向、闭眼切换和循环衔接（需要 Swift 编译器及 JDK 17+）。

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
Android 构建会校验 APK ZIP 与全部 native `PT_LOAD` 段的 16 KB 页对齐。

当前移动外壳提供精简启动页、数据目录复制、中文文档和运行时信息。
两端中文文档入口使用 `https://www.chef25.com/guides/sillytavern/?hideHeader=1`，
由网页隐藏重复的品牌与主导航区域；文档内跳转继续保留该参数。
设置页「危险操作 → 重置本地数据」需完整输入“确认重置”，永久删除本机角色、聊天、API 配置及酒馆 WebView 的 Cookie / 缓存。请先自行备份。未启动过酒馆时立即执行；本次已启动过时只保存重置请求，须彻底关闭 App（Android 从系统设置强行停止；iOS 从多任务界面划掉）并重新打开后执行，切到后台不会执行。重置失败可能已删除部分数据，启动会被阻止，可在设置中重试；中断后下次打开会继续重试。删除范围固定为 `chef25-data/`（含 `config.yaml`），Android 另外清除可重新解压的 `sillytavern/`。安装资源、其他目录和系统诊断日志不删除；端口仍为 8123。重置不会自动启动酒馆。
Desktop 的端口编辑、ZIP 导入导出和更新功能尚未移植到这个移动可行性版本。
两端 App 图标复用 Desktop 的橙底 ChefHat 标记，并分别提供 iOS 多倍率资源、Android
adaptive 图标和 API 24–25 的 legacy fallback；统一生成入口是
`spike/assets/generate-icons.sh`。
长期移动后台、实体 Android 设备、全部插件/供应商兼容和产品级包体优化仍未验证。
发布、签名、TestFlight 和 Cloudflare 配置见
[Mobile 发布流程](docs/releasing.md)。
