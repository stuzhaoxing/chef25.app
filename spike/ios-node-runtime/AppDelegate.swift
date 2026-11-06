import UIKit
import WebKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = RuntimeViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

final class RuntimeViewController: UIViewController, WKNavigationDelegate, UIGestureRecognizerDelegate {
    private enum Palette {
        static let paper = UIColor(red: 0.984, green: 0.976, blue: 0.961, alpha: 1)
        static let sidebar = UIColor(red: 0.953, green: 0.945, blue: 0.914, alpha: 1)
        static let ink = UIColor(red: 0.188, green: 0.200, blue: 0.173, alpha: 1)
        static let muted = UIColor(red: 0.518, green: 0.529, blue: 0.478, alpha: 1)
        static let accent = UIColor(red: 0.925, green: 0.396, blue: 0.255, alpha: 1)
        static let accentSoft = UIColor(red: 0.973, green: 0.898, blue: 0.847, alpha: 1)
        static let line = UIColor(red: 0.902, green: 0.890, blue: 0.851, alpha: 1)
        static let card = UIColor(red: 1, green: 0.992, blue: 0.976, alpha: 1)
        static let green = UIColor(red: 0.133, green: 0.643, blue: 0.278, alpha: 1)
        static let amber = UIColor(red: 0.847, green: 0.608, blue: 0.302, alpha: 1)
    }

    private let mainPane = UIView()
    private let mainContent = UIView()
    private let drawerDismiss = UIButton(type: .custom)
    private var drawerProgress: CGFloat = 0
    private var drawerGestureStart: CGFloat = 0
    private let header = UIView()
    private let contentContainer = UIView()
    private let drawerOverlay = UIView()
    private let drawerPanel = UIView()
    private let drawerMenu = UIStackView()
    private let menuButton = UIButton(type: .system)
    private let mascot = ChefMascotView()
    private var drawerOpen = false
    private let homeButton = UIButton(type: .system)
    private let pageTitle = UILabel()
    private let pageSubtitle = TavernBrandView()

    private let launcherScroll = UIScrollView()
    private let dataScroll = UIScrollView()
    private let settingsScroll = UIScrollView()
    private let docsWebView = WKWebView(frame: .zero)
    private let tavernWebView = WKWebView(frame: .zero)

    private let primaryButton = UIButton(type: .system)
    private var resetBusy = false
    private lazy var resetButton = makeSecondaryButton(title: "重置本地数据", image: "trash")
    private var resetMarker: URL { dataRoot.deletingLastPathComponent().appendingPathComponent("chef25-reset-pending") }
    private var resetPending: Bool { FileManager.default.fileExists(atPath: resetMarker.path) }
    private let settingsRuntimeValue = UILabel()
    private let settingsStatusValue = UILabel()

    private var tabButtons: [UIButton] = []
    private var contentTopWithHeader: NSLayoutConstraint!
    private var contentTopFull: NSLayoutConstraint!
    private var contentBottomFull: NSLayoutConstraint!
    private var currentTab = 0
    private var runtimeStarted = false
    private var runtimeReady = false
    private var tavernEntered = false
    private var tavernLoaded = false
    private var docsLoaded = false
    private var pollAttempts = 0
    private var automationStarted = false
    private let maximumPollAttempts = 240

    override var preferredStatusBarStyle: UIStatusBarStyle {
        tavernEntered ? .lightContent : .darkContent
    }

    private var dataRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("chef25-data", isDirectory: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.paper
        mainContent.backgroundColor = Palette.paper
        mainPane.translatesAutoresizingMaskIntoConstraints = false
        mainContent.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mainPane)
        mainPane.addSubview(mainContent)
        mainContent.clipsToBounds = true
        NSLayoutConstraint.activate([
            mainPane.topAnchor.constraint(equalTo: view.topAnchor),
            mainPane.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            mainPane.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mainPane.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mainContent.topAnchor.constraint(equalTo: mainPane.topAnchor),
            mainContent.bottomAnchor.constraint(equalTo: mainPane.bottomAnchor),
            mainContent.leadingAnchor.constraint(equalTo: mainPane.leadingAnchor),
            mainContent.trailingAnchor.constraint(equalTo: mainPane.trailingAnchor),
        ])
        configureHeader()
        configureContent()
        configureLauncher()
        configureDataPage()
        configureSettingsPage()
        configureWebViews()
        configureDrawer()
        refreshNavigation()

        NotificationCenter.default.addObserver(self, selector: #selector(applicationWillResignActive),
            name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshMascotMotion),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        if resetPending {
            performLocalReset()
            return
        }

        if ProcessInfo.processInfo.environment["CHEF25_AUTO_START"] == "1"
            || ProcessInfo.processInfo.environment["CHEF25_UI_TEST_MESSAGE"] != nil {
            startRuntime()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        setDrawer(open: false, animated: false)
        super.viewWillTransition(to: size, with: coordinator)
    }

    deinit {
        mascot.setAnimating(false)
        NotificationCenter.default.removeObserver(self)
    }

    private func configureHeader() {
        header.translatesAutoresizingMaskIntoConstraints = false
        header.backgroundColor = Palette.sidebar
        mainContent.addSubview(header)

        menuButton.translatesAutoresizingMaskIntoConstraints = false
        menuButton.setImage(UIImage(systemName: "line.3.horizontal"), for: .normal)
        menuButton.tintColor = Palette.ink
        menuButton.accessibilityLabel = "展开菜单"
        menuButton.addTarget(self, action: #selector(openDrawer), for: .touchUpInside)
        header.addSubview(menuButton)

        let brandMark = BrandMarkView()
        brandMark.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(brandMark)

        let brandCopy = UIStackView()
        brandCopy.translatesAutoresizingMaskIntoConstraints = false
        brandCopy.axis = .vertical
        brandCopy.spacing = -1
        let brandTitle = UILabel()
        brandTitle.text = "25小厨"
        brandTitle.textColor = Palette.ink
        brandTitle.font = .systemFont(ofSize: 20, weight: .heavy)
        let brandSubtitle = UILabel()
        brandSubtitle.text = "CHEF25"
        brandSubtitle.textColor = Palette.muted
        brandSubtitle.font = .systemFont(ofSize: 8, weight: .semibold)
        brandSubtitle.setContentHuggingPriority(.required, for: .vertical)
        brandSubtitle.transform = CGAffineTransform(translationX: 1, y: 0)
        brandCopy.addArrangedSubview(brandTitle)
        brandCopy.addArrangedSubview(brandSubtitle)
        header.addSubview(brandCopy)

        let pageCopy = UIStackView()
        pageCopy.translatesAutoresizingMaskIntoConstraints = false
        pageCopy.axis = .vertical
        pageCopy.alignment = .trailing
        pageCopy.spacing = 2
        pageTitle.textColor = Palette.ink
        pageTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        pageTitle.textAlignment = .right
        pageCopy.addArrangedSubview(pageTitle)
        pageSubtitle.translatesAutoresizingMaskIntoConstraints = false
        pageSubtitle.widthAnchor.constraint(equalToConstant: 108).isActive = true
        pageSubtitle.heightAnchor.constraint(equalToConstant: 18).isActive = true
        pageCopy.addArrangedSubview(pageSubtitle)
        header.addSubview(pageCopy)

        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = Palette.line
        header.addSubview(divider)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: mainContent.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: mainContent.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: mainContent.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 64),

            menuButton.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 4),
            menuButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            menuButton.widthAnchor.constraint(equalToConstant: 44),
            menuButton.heightAnchor.constraint(equalToConstant: 44),
            brandMark.leadingAnchor.constraint(equalTo: menuButton.trailingAnchor, constant: 2),
            brandMark.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            brandMark.widthAnchor.constraint(equalToConstant: 36),
            brandMark.heightAnchor.constraint(equalToConstant: 36),

            brandCopy.leadingAnchor.constraint(equalTo: brandMark.trailingAnchor, constant: 10),
            brandCopy.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            pageCopy.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -18),
            pageCopy.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            pageCopy.leadingAnchor.constraint(greaterThanOrEqualTo: brandCopy.trailingAnchor, constant: 8),

            divider.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
        ])
    }

    private func configureContent() {
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        mainContent.addSubview(contentContainer)
        contentTopWithHeader = contentContainer.topAnchor.constraint(equalTo: header.bottomAnchor)
        contentTopFull = contentContainer.topAnchor.constraint(equalTo: mainContent.safeAreaLayoutGuide.topAnchor)
        contentBottomFull = contentContainer.bottomAnchor.constraint(
            equalTo: mainContent.safeAreaLayoutGuide.bottomAnchor
        )
        NSLayoutConstraint.activate([
            contentTopWithHeader,
            contentBottomFull,
            contentContainer.leadingAnchor.constraint(equalTo: mainContent.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: mainContent.trailingAnchor),
        ])
        [
            launcherScroll,
            dataScroll,
            settingsScroll,
            docsWebView,
            tavernWebView,
        ].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentContainer.addSubview($0)
            NSLayoutConstraint.activate([
                $0.topAnchor.constraint(equalTo: contentContainer.topAnchor),
                $0.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
                $0.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
                $0.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            ])
        }

        var homeConfiguration = UIButton.Configuration.plain()
        homeConfiguration.title = "返回小厨"
        homeConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var attributes = incoming
            attributes.font = .systemFont(ofSize: 12, weight: .semibold)
            return attributes
        }
        homeConfiguration.baseForegroundColor = Palette.ink
        homeConfiguration.background.backgroundColor = Palette.paper
        homeConfiguration.cornerStyle = .capsule
        homeConfiguration.contentInsets = NSDirectionalEdgeInsets(
            top: 4,
            leading: 8,
            bottom: 4,
            trailing: 8
        )
        homeButton.configuration = homeConfiguration
        homeButton.accessibilityLabel = "返回小厨"
        homeButton.addTarget(self, action: #selector(returnToLauncher), for: .touchUpInside)
        homeButton.isHidden = true
        contentContainer.addSubview(homeButton)
        homeButton.layer.shadowColor = UIColor.black.cgColor
        homeButton.layer.shadowOpacity = 0.22
        homeButton.layer.shadowRadius = 6
        homeButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        homeButton.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragHomeButton(_:))))

    }

    private var homeDockRight = true
    private var homeVerticalFraction: CGFloat = 0.5
    private var homeDragOrigin = CGPoint.zero
    private var homeDragging = false
    private var homeSnapAnimator: UIViewPropertyAnimator?

    private func boundedHomeOrigin(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(8, point.x), max(8, contentContainer.bounds.width - homeButton.bounds.width - 8)),
                y: min(max(8, point.y), max(8, contentContainer.bounds.height - homeButton.bounds.height - 8)))
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !homeDragging, homeSnapAnimator == nil else { return }
        homeButton.bounds.size = CGSize(width: max(76, homeButton.sizeThatFits(CGSize(width: 200, height: 30)).width), height: 30)
        positionHomeButton()
    }

    private func positionHomeButton() {
        let height = max(0, contentContainer.bounds.height - homeButton.bounds.height - 16)
        homeButton.frame.origin = boundedHomeOrigin(CGPoint(
            x: homeDockRight ? contentContainer.bounds.width - homeButton.bounds.width - 8 : 8,
            y: 8 + height * homeVerticalFraction))
    }

    @objc private func dragHomeButton(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began {
            let visibleFrame = homeButton.layer.presentation()?.frame
            homeSnapAnimator?.stopAnimation(true)
            homeSnapAnimator = nil
            if let visibleFrame { homeButton.frame = visibleFrame }
            homeDragging = true
            homeDragOrigin = homeButton.frame.origin
        }
        if gesture.state == .changed || gesture.state == .began || gesture.state == .ended {
            let delta = gesture.translation(in: contentContainer)
            homeButton.frame.origin = boundedHomeOrigin(CGPoint(x: homeDragOrigin.x + delta.x, y: homeDragOrigin.y + delta.y))
        }
        if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
            homeDragging = false
            homeDockRight = homeButton.center.x >= contentContainer.bounds.midX
            homeVerticalFraction = min(1, max(0, (homeButton.frame.minY - 8) / max(1, contentContainer.bounds.height - homeButton.bounds.height - 16)))
            guard !UIAccessibility.isReduceMotionEnabled else { positionHomeButton(); return }
            // Next.js dev indicator uses a roughly 491 ms spring snap.
            let animator = UIViewPropertyAnimator(duration: 0.49122, dampingRatio: 0.78) { self.positionHomeButton() }
            homeSnapAnimator = animator
            animator.addCompletion { [weak self] _ in
                self?.homeSnapAnimator = nil
                self?.view.setNeedsLayout()
            }
            animator.startAnimation()
        }
    }

    private func configureDrawer() {
        drawerOverlay.translatesAutoresizingMaskIntoConstraints = false
        drawerOverlay.isHidden = true
        drawerOverlay.accessibilityViewIsModal = true
        view.insertSubview(drawerOverlay, belowSubview: mainPane)
        drawerPanel.translatesAutoresizingMaskIntoConstraints = false
        drawerPanel.backgroundColor = Palette.paper
        drawerOverlay.addSubview(drawerPanel)
        let close = UIButton(type: .system)
        close.translatesAutoresizingMaskIntoConstraints = false
        close.setTitle("25小厨", for: .normal)
        close.contentHorizontalAlignment = .leading
        close.titleLabel?.font = .systemFont(ofSize: 20, weight: .heavy)
        let drawerMark = BrandMarkView()
        drawerMark.translatesAutoresizingMaskIntoConstraints = false
        drawerPanel.addSubview(drawerMark)
        close.tintColor = Palette.ink
        close.accessibilityLabel = "关闭菜单"
        close.addTarget(self, action: #selector(closeDrawer), for: .touchUpInside)
        drawerPanel.addSubview(close)
        drawerMenu.translatesAutoresizingMaskIntoConstraints = false
        drawerMenu.axis = .vertical
        drawerMenu.spacing = 8
        let menuScroll = UIScrollView()
        menuScroll.translatesAutoresizingMaskIntoConstraints = false
        drawerPanel.addSubview(menuScroll)
        menuScroll.addSubview(drawerMenu)
        let about = UIButton(type: .system)
        about.translatesAutoresizingMaskIntoConstraints = false
        var aboutConfig = UIButton.Configuration.plain()
        aboutConfig.title = "关于"
        aboutConfig.image = UIImage(systemName: "info.circle")
        aboutConfig.imagePadding = 12
        aboutConfig.baseForegroundColor = Palette.muted
        about.configuration = aboutConfig
        about.contentHorizontalAlignment = .leading
        about.addTarget(self, action: #selector(drawerAbout), for: .touchUpInside)
        drawerPanel.addSubview(about)
        let tabs = [("我的酒馆", "cup.and.saucer.fill"), ("本地数据", "folder.fill"),
                    ("中文文档", "questionmark.circle.fill"), ("设置", "gearshape.fill")]
        for (index, tab) in tabs.enumerated() {
            var configuration = UIButton.Configuration.plain()
            configuration.title = tab.0
            configuration.image = UIImage(systemName: tab.1)
            configuration.imagePadding = 14
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
            configuration.background.cornerRadius = 8
            let button = UIButton(configuration: configuration)
            button.contentHorizontalAlignment = .leading
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
            button.tag = index
            button.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
            drawerMenu.addArrangedSubview(button)
            tabButtons.append(button)
        }
        let preferredWidth = drawerPanel.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.82)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            preferredWidth,
            drawerOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            drawerOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            drawerOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            drawerOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            drawerPanel.topAnchor.constraint(equalTo: drawerOverlay.topAnchor),
            drawerPanel.bottomAnchor.constraint(equalTo: drawerOverlay.bottomAnchor),
            drawerPanel.leadingAnchor.constraint(equalTo: drawerOverlay.leadingAnchor),
            drawerPanel.widthAnchor.constraint(lessThanOrEqualToConstant: 380),
            close.topAnchor.constraint(equalTo: drawerPanel.safeAreaLayoutGuide.topAnchor, constant: 8),
            drawerMark.leadingAnchor.constraint(equalTo: drawerPanel.leadingAnchor, constant: 22),
            drawerMark.centerYAnchor.constraint(equalTo: close.centerYAnchor),
            drawerMark.widthAnchor.constraint(equalToConstant: 30),
            drawerMark.heightAnchor.constraint(equalToConstant: 30),
            close.leadingAnchor.constraint(equalTo: drawerMark.trailingAnchor, constant: 10),
            close.trailingAnchor.constraint(equalTo: drawerPanel.trailingAnchor, constant: -16),
            close.heightAnchor.constraint(equalToConstant: 48),
            menuScroll.topAnchor.constraint(equalTo: close.bottomAnchor, constant: 20),
            menuScroll.leadingAnchor.constraint(equalTo: drawerPanel.leadingAnchor, constant: 22),
            menuScroll.trailingAnchor.constraint(equalTo: drawerPanel.trailingAnchor, constant: -22),
            menuScroll.bottomAnchor.constraint(equalTo: about.topAnchor, constant: -12),
            drawerMenu.topAnchor.constraint(equalTo: menuScroll.contentLayoutGuide.topAnchor),
            drawerMenu.bottomAnchor.constraint(equalTo: menuScroll.contentLayoutGuide.bottomAnchor),
            drawerMenu.leadingAnchor.constraint(equalTo: menuScroll.contentLayoutGuide.leadingAnchor),
            drawerMenu.trailingAnchor.constraint(equalTo: menuScroll.contentLayoutGuide.trailingAnchor),
            drawerMenu.widthAnchor.constraint(equalTo: menuScroll.frameLayoutGuide.widthAnchor),
            about.leadingAnchor.constraint(equalTo: drawerPanel.leadingAnchor, constant: 22),
            about.trailingAnchor.constraint(equalTo: drawerPanel.trailingAnchor, constant: -22),
            about.bottomAnchor.constraint(equalTo: drawerPanel.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            about.heightAnchor.constraint(equalToConstant: 48),
        ])
        drawerDismiss.translatesAutoresizingMaskIntoConstraints = false
        drawerDismiss.backgroundColor = .clear
        drawerDismiss.accessibilityLabel = "关闭侧边栏"
        drawerDismiss.addTarget(self, action: #selector(closeDrawer), for: .touchUpInside)
        drawerDismiss.isHidden = true
        mainContent.addSubview(drawerDismiss)
        NSLayoutConstraint.activate([
            drawerDismiss.topAnchor.constraint(equalTo: mainContent.topAnchor),
            drawerDismiss.bottomAnchor.constraint(equalTo: mainContent.bottomAnchor),
            drawerDismiss.leadingAnchor.constraint(equalTo: mainContent.leadingAnchor),
            drawerDismiss.trailingAnchor.constraint(equalTo: mainContent.trailingAnchor),
        ])
        let pan = UIPanGestureRecognizer(target: self, action: #selector(drawerPanned(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        view.addGestureRecognizer(pan)
        for scroll in [launcherScroll, dataScroll, settingsScroll, docsWebView.scrollView] {
            scroll.panGestureRecognizer.require(toFail: pan)
        }
    }

    @objc private func drawerAbout() {
        showAbout()
    }

    func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        guard let pan = gesture as? UIPanGestureRecognizer,
              !tavernEntered, presentedViewController == nil else { return false }
        let velocity = pan.velocity(in: view)
        guard abs(velocity.x) > abs(velocity.y) * 1.4 else { return false }
        return drawerOpen ? velocity.x < 0 :
            pan.location(in: view).x - pan.translation(in: view).x <= 28 && velocity.x > 0
    }

    @objc private func drawerPanned(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            if let presentation = mainPane.layer.presentation(), drawerPanel.bounds.width > 0 {
                drawerProgress = max(0, min(1, presentation.transform.m41 / drawerPanel.bounds.width))
            }
            mainPane.layer.removeAllAnimations()
            drawerPanel.layer.removeAllAnimations()
            drawerGestureStart = drawerProgress
            view.layoutIfNeeded()
            renderDrawer(drawerProgress)
            drawerOverlay.isHidden = false
            drawerDismiss.isHidden = false
            mascot.setAnimating(false)
        case .changed:
            renderDrawer(max(0, min(1, drawerGestureStart + pan.translation(in: view).x / drawerPanel.bounds.width)))
        case .ended:
            let velocity = pan.velocity(in: view).x
            setDrawer(open: velocity > 250 || (velocity >= -250 && drawerProgress > 0.5))
        case .cancelled, .failed:
            setDrawer(open: drawerOpen)
        default: break
        }
    }

    private func renderDrawer(_ progress: CGFloat) {
        drawerProgress = progress
        let width = drawerPanel.bounds.width
        mainPane.transform = CGAffineTransform(translationX: width * progress, y: 0)
        drawerPanel.transform = CGAffineTransform(translationX: width * (progress - 1), y: 0)
        mainContent.layer.cornerRadius = progress > 0 ? 22 : 0
        mainPane.layer.shadowColor = UIColor.black.cgColor
        mainPane.layer.shadowOffset = CGSize(width: -6, height: 0)
        mainPane.layer.shadowRadius = 14
        mainPane.layer.shadowOpacity = progress > 0 ? 0.14 : 0
    }

    @objc private func openDrawer() { setDrawer(open: true) }
    @objc private func closeDrawer() { setDrawer(open: false) }

    private func setDrawer(open: Bool, animated: Bool = true) {
        guard !(open && tavernEntered) else { return }
        drawerOpen = open
        view.layoutIfNeeded()
        renderDrawer(drawerProgress)
        drawerOverlay.isHidden = false
        drawerDismiss.isHidden = false
        header.accessibilityElementsHidden = open
        contentContainer.accessibilityElementsHidden = open
        UIView.animate(withDuration: animated && !UIAccessibility.isReduceMotionEnabled ? (open ? 0.28 : 0.22) : 0,
            delay: 0, options: [.beginFromCurrentState, .curveEaseOut], animations: {
                self.renderDrawer(open ? 1 : 0)
            }, completion: { _ in
                guard self.drawerOpen == open else { return }
                self.drawerOverlay.isHidden = !open
                self.drawerDismiss.isHidden = !open
                UIAccessibility.post(notification: .screenChanged, argument: open ? self.tabButtons[self.currentTab] : self.menuButton)
            })
        refreshMascotMotion()
    }

    override func accessibilityPerformEscape() -> Bool {
        guard drawerOpen else { return false }
        closeDrawer()
        return true
    }

    @objc private func applicationWillResignActive() {
        setDrawer(open: false, animated: false)
        mascot.setAnimating(false)
    }

    @objc private func refreshMascotMotion() {
        mascot.setAnimating(currentTab == 0 && !tavernEntered && !drawerOpen
            && UIApplication.shared.applicationState == .active && !UIAccessibility.isReduceMotionEnabled)
    }

    private func configureLauncher() {
        launcherScroll.alwaysBounceVertical = true
        launcherScroll.showsVerticalScrollIndicator = false

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 12
        let stage = UIView()
        stage.translatesAutoresizingMaskIntoConstraints = false
        launcherScroll.addSubview(stage)
        stage.addSubview(stack)
        let preferredHeight = stage.heightAnchor.constraint(equalTo: launcherScroll.frameLayoutGuide.heightAnchor)
        preferredHeight.priority = UILayoutPriority(249)

        let hero = UIView()
        let heroStack = UIStackView()
        heroStack.translatesAutoresizingMaskIntoConstraints = false
        heroStack.axis = .vertical
        heroStack.alignment = .center
        heroStack.spacing = 6
        hero.addSubview(heroStack)

        mascot.translatesAutoresizingMaskIntoConstraints = false
        heroStack.addArrangedSubview(mascot)
        heroStack.setCustomSpacing(6, after: mascot)

        let heroTitle = UILabel()
        heroTitle.text = "故事，你来写。"
        heroTitle.textColor = Palette.ink
        heroTitle.font = .systemFont(ofSize: 24, weight: .semibold)
        heroTitle.textAlignment = .center
        heroStack.addArrangedSubview(heroTitle)

        let heroSubtitle = UILabel()
        heroSubtitle.text = "开场，交给小厨。"
        heroSubtitle.textColor = Palette.muted
        heroSubtitle.font = .systemFont(ofSize: 13)
        heroSubtitle.textAlignment = .center
        heroStack.addArrangedSubview(heroSubtitle)

        NSLayoutConstraint.activate([
            hero.heightAnchor.constraint(greaterThanOrEqualToConstant: 224),
            heroStack.topAnchor.constraint(equalTo: hero.topAnchor, constant: 12),
            heroStack.leadingAnchor.constraint(equalTo: hero.leadingAnchor, constant: 20),
            heroStack.trailingAnchor.constraint(equalTo: hero.trailingAnchor, constant: -20),
            heroStack.bottomAnchor.constraint(equalTo: hero.bottomAnchor, constant: -6),
            mascot.widthAnchor.constraint(equalToConstant: 200),
            mascot.heightAnchor.constraint(equalToConstant: 150),
        ])
        stack.addArrangedSubview(hero)

        primaryButton.translatesAutoresizingMaskIntoConstraints = false
        var primaryConfiguration = UIButton.Configuration.plain()
        primaryConfiguration.title = "一键启动酒馆"
        primaryConfiguration.image = UIImage(systemName: "play.fill")
        primaryConfiguration.imagePadding = 9
        primaryConfiguration.background.backgroundColor = Palette.accent
        primaryConfiguration.baseForegroundColor = .white
        primaryConfiguration.background.cornerRadius = 8
        primaryConfiguration.contentInsets = NSDirectionalEdgeInsets(
            top: 12,
            leading: 20,
            bottom: 12,
            trailing: 20
        )
        primaryConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            attributes.font = .systemFont(ofSize: 14, weight: .semibold)
            return attributes
        }
        primaryButton.configuration = primaryConfiguration
        primaryButton.addTarget(self, action: #selector(primaryAction), for: .touchUpInside)
        let primaryRow = UIView()
        primaryRow.translatesAutoresizingMaskIntoConstraints = false
        primaryRow.addSubview(primaryButton)
        NSLayoutConstraint.activate([
            primaryButton.topAnchor.constraint(equalTo: primaryRow.topAnchor),
            primaryButton.bottomAnchor.constraint(equalTo: primaryRow.bottomAnchor),
            primaryButton.centerXAnchor.constraint(equalTo: primaryRow.centerXAnchor),
            primaryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 190),
            primaryButton.heightAnchor.constraint(equalToConstant: 46),
        ])
        stack.addArrangedSubview(primaryRow)


        let preferredWidth = stack.widthAnchor.constraint(equalTo: launcherScroll.frameLayoutGuide.widthAnchor, constant: -40)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            preferredWidth,
            stage.topAnchor.constraint(equalTo: launcherScroll.contentLayoutGuide.topAnchor),
            stage.bottomAnchor.constraint(equalTo: launcherScroll.contentLayoutGuide.bottomAnchor),
            stage.leadingAnchor.constraint(equalTo: launcherScroll.contentLayoutGuide.leadingAnchor),
            stage.trailingAnchor.constraint(equalTo: launcherScroll.contentLayoutGuide.trailingAnchor),
            stage.widthAnchor.constraint(equalTo: launcherScroll.frameLayoutGuide.widthAnchor),
            stage.heightAnchor.constraint(greaterThanOrEqualTo: launcherScroll.frameLayoutGuide.heightAnchor),
            preferredHeight,
            stack.topAnchor.constraint(greaterThanOrEqualTo: stage.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: stage.bottomAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: stage.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: stage.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: stage.trailingAnchor, constant: -20),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 620),
            stack.centerXAnchor.constraint(equalTo: launcherScroll.frameLayoutGuide.centerXAnchor),
        ])
    }

    private func configureDataPage() {
        dataScroll.alwaysBounceVertical = true
        dataScroll.showsVerticalScrollIndicator = false
        let stack = verticalPageStack(in: dataScroll)

        let storageCard = makeCard(
            title: "存储目录",
            subtitle: ""
        )
        guard let storageStack = storageCard.subviews.last as? UIStackView else { return }
        let pathLabel = makeBodyLabel(dataRoot.path)
        pathLabel.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        pathLabel.numberOfLines = 3
        storageStack.addArrangedSubview(pathLabel)

        let copyButton = makeSecondaryButton(title: "复制路径", image: "doc.on.doc")
        copyButton.addTarget(self, action: #selector(copyDataPath), for: .touchUpInside)
        storageStack.addArrangedSubview(copyButton)
        stack.addArrangedSubview(storageCard)
    }

    private func configureSettingsPage() {
        settingsScroll.alwaysBounceVertical = true
        settingsScroll.showsVerticalScrollIndicator = false
        let stack = verticalPageStack(in: settingsScroll)

        let launchCard = makeCard(
            title: "启动端口",
            subtitle: ""
        )
        if let launchStack = launchCard.subviews.last as? UIStackView {
            launchStack.addArrangedSubview(makeInfoRow(label: "当前地址", value: "127.0.0.1:8123"))
        }
        stack.addArrangedSubview(launchCard)

        let runtimeCard = makeCard(
            title: "内置运行时",
            subtitle: ""
        )
        if let runtimeStack = runtimeCard.subviews.last as? UIStackView {
            settingsRuntimeValue.text = "v24.22.1"
            settingsRuntimeValue.textColor = Palette.muted
            settingsRuntimeValue.font = .systemFont(ofSize: 12)
            settingsStatusValue.text = "尚未启动"
            settingsStatusValue.textColor = Palette.muted
            settingsStatusValue.font = .systemFont(ofSize: 12)
            let runtimeValues = UIStackView(arrangedSubviews: [
                makeInfoRow(label: "Node.js", valueLabel: settingsRuntimeValue),
                makeInfoRow(label: "SillyTavern", value: "1.19.0"),
                makeInfoRow(label: "运行状态", valueLabel: settingsStatusValue),
            ])
            runtimeValues.axis = .vertical
            runtimeValues.spacing = 9
            runtimeStack.addArrangedSubview(runtimeValues)
        }
        stack.addArrangedSubview(runtimeCard)
        let dangerCard = makeCard(title: "危险操作", subtitle:
            "永久清除本机角色、聊天、API 配置及酒馆缓存，请先自行备份。已启动过酒馆时，将在彻底关闭 App 并重新打开后执行。")
        if let dangerStack = dangerCard.subviews.last as? UIStackView {
            resetButton.configuration?.baseForegroundColor = UIColor(red: 0.706, green: 0.239, blue: 0.196, alpha: 1)
            resetButton.addTarget(self, action: #selector(confirmLocalReset), for: .touchUpInside)
            dangerStack.addArrangedSubview(resetButton)
        }
        stack.addArrangedSubview(dangerCard)


    }

    private func showResetNotice(_ message: String) {
        present(ChefDialogController(title: "重置本地数据", message: message), animated: true)
    }

    @objc private func confirmLocalReset() {
        guard !resetBusy else { return }
        let timing = runtimeStarted
            ? "本次已启动过酒馆，确认后请从多任务界面划掉 App，再重新打开执行重置。"
            : "确认后立即执行，下次启动酒馆将重新初始化。"
        let dialog = ChefDialogController(title: "重置本地数据？",
            message: "角色、聊天、API 配置及酒馆缓存将永久删除，无法撤销，请先自行备份。\n" + timing,
            phrase: "确认重置", actionTitle: "确认重置") { [weak self] in
            guard let self else { return }
            do {
                try Data([1]).write(to: self.resetMarker, options: .atomic)
                if self.runtimeStarted {
                    self.showResetNotice("已安排重置。请从多任务界面划掉 App，再重新打开。返回首页或切到后台不会执行重置。")
                } else { self.performLocalReset() }
            } catch { self.showResetNotice("无法安排重置，请重试。") }
        }
        present(dialog, animated: true)
    }

    private func performLocalReset() {
        guard !runtimeStarted, !resetBusy else { return }
        resetBusy = true
        resetButton.isEnabled = false
        resetButton.configuration?.title = "正在重置…"
        let target = dataRoot
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // removeItem unlinks symlinks instead of following them. Bundle stays intact.
                let manager = FileManager.default
                do { try manager.removeItem(at: target) }
                catch let error as NSError where error.domain == NSCocoaErrorDomain
                    && error.code == NSFileNoSuchFileError { /* Already empty. */ }
                DispatchQueue.main.async {
                    let store = self.tavernWebView.configuration.websiteDataStore
                    store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
                        do {
                            try FileManager.default.removeItem(at: self.resetMarker)
                            self.finishLocalReset(true)
                        } catch { self.finishLocalReset(false) }
                    }
                }
            } catch {
                DispatchQueue.main.async { self.finishLocalReset(false) }
            }
        }
    }

    private func finishLocalReset(_ completed: Bool) {
        resetBusy = false
        resetButton.isEnabled = true
        resetButton.configuration?.title = "重置本地数据"
        // Launch recovery runs before viewDidAppear, so defer the alert until visible.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.showResetNotice(completed ? "本地数据已重置，下次启动酒馆将重新初始化。"
                : "重置失败，可能已清除部分数据。请重试；完成前无法启动酒馆。")
        }
    }

    private func configureWebViews() {
        docsWebView.navigationDelegate = self
        docsWebView.isHidden = true
        docsWebView.backgroundColor = Palette.paper

        tavernWebView.navigationDelegate = self
        tavernWebView.isHidden = true
        tavernWebView.backgroundColor = .black
        tavernWebView.configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        tavernWebView.configuration.userContentController.add(self, name: "chef25Automation")

        launcherScroll.isHidden = false
        dataScroll.isHidden = true
        settingsScroll.isHidden = true
    }

    private func verticalPageStack(in scrollView: UIScrollView) -> UIStackView {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 12
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 620),
            stack.centerXAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerXAnchor),
        ])
        return stack
    }

    private func makeCard(title: String, subtitle: String) -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = Palette.card
        card.layer.cornerRadius = 10
        card.layer.cornerCurve = .continuous
        card.layer.borderColor = Palette.line.cgColor
        card.layer.borderWidth = 1

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 7
        card.addSubview(stack)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = Palette.ink
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        stack.addArrangedSubview(titleLabel)
        if !subtitle.isEmpty {
            stack.addArrangedSubview(makeBodyLabel(subtitle))
        }

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
        ])
        return card
    }

    private func makeBodyLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = Palette.muted
        label.font = .systemFont(ofSize: 12)
        label.numberOfLines = 0
        return label
    }

    private func makeSecondaryButton(title: String, image: String) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.image = UIImage(systemName: image)
        configuration.imagePadding = 7
        configuration.baseForegroundColor = Palette.ink
        configuration.background.backgroundColor = Palette.sidebar
        configuration.cornerStyle = .medium
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 13, bottom: 10, trailing: 13)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            attributes.font = .systemFont(ofSize: 12, weight: .medium)
            return attributes
        }
        return UIButton(configuration: configuration)
    }

    private func makeInfoRow(label: String, value: String) -> UIView {
        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.textColor = Palette.muted
        valueLabel.font = .systemFont(ofSize: 12)
        return makeInfoRow(label: label, valueLabel: valueLabel)
    }

    private func makeInfoRow(label: String, valueLabel: UILabel) -> UIView {
        let key = UILabel()
        key.text = label
        key.textColor = Palette.muted
        key.font = .systemFont(ofSize: 12)
        valueLabel.textAlignment = .right
        let row = UIStackView(arrangedSubviews: [key, valueLabel])
        row.axis = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 16
        return row
    }

    @objc private func tabTapped(_ sender: UIButton) {
        setTab(sender.tag)
        closeDrawer()
    }

    private func setTab(_ index: Int) {
        guard (0..<tabButtons.count).contains(index) else { return }
        currentTab = index
        if index == 2 && !docsLoaded {
            docsLoaded = true
            docsWebView.load(URLRequest(url: URL(string: "https://www.chef25.com/guides/sillytavern/?hideHeader=1")!))
        }
        refreshNavigation()
    }

    private func refreshNavigation() {
        let inTavern = currentTab == 0 && tavernEntered
        header.isHidden = inTavern
        if inTavern { setDrawer(open: false, animated: false) }
        launcherScroll.isHidden = currentTab != 0 || tavernEntered
        dataScroll.isHidden = currentTab != 1
        docsWebView.isHidden = currentTab != 2
        settingsScroll.isHidden = currentTab != 3
        tavernWebView.isHidden = !inTavern
        homeButton.isHidden = !inTavern
        contentTopWithHeader.isActive = !inTavern
        contentTopFull.isActive = inTavern
        mainContent.backgroundColor = inTavern ? UIColor(white: 0.09, alpha: 1) : Palette.paper
        contentContainer.backgroundColor = inTavern ? UIColor(white: 0.09, alpha: 1) : .clear
        tavernWebView.scrollView.contentInsetAdjustmentBehavior = .never
        setNeedsStatusBarAppearanceUpdate()
        refreshMascotMotion()

        let titles = ["我的酒馆", "本地数据", "中文文档", "设置"]
        pageTitle.text = titles[min(currentTab, titles.count - 1)]
        pageSubtitle.isHidden = currentTab != 0
        for (index, button) in tabButtons.enumerated() {
            button.accessibilityTraits = index == currentTab ? [.button, .selected] : .button
            button.configuration?.baseForegroundColor =
                index == currentTab ? UIColor(red: 0.812, green: 0.396, blue: 0.247, alpha: 1) : Palette.muted
            button.configuration?.background.backgroundColor =
                index == currentTab ? Palette.accentSoft : .clear
        }
    }

    @objc private func returnToLauncher() {
        tavernEntered = false
        refreshNavigation()
        updateRuntimeState(.running)
    }

    @objc private func primaryAction() {
        if runtimeReady {
            enterTavern()
        } else {
            startRuntime()
        }
    }

    private func startRuntime() {
        guard !resetBusy, !resetPending else {
            showResetNotice("重置尚未完成。请在设置中重试；若本次已启动过酒馆，请彻底关闭 App 后重新打开。")
            return
        }
        guard !runtimeStarted else { return }
        runtimeStarted = true
        updateRuntimeState(.starting)

        guard let projectPath = Bundle.main.path(
            forResource: "server",
            ofType: "js",
            inDirectory: "nodejs-project"
        ) else {
            updateRuntimeState(.failed("应用包中缺少 nodejs-project/server.js"))
            return
        }

        do {
            try FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: true)
        } catch {
            updateRuntimeState(.failed("无法创建可写数据目录：\(error.localizedDescription)"))
            return
        }
        Chef25StartNode(projectPath, dataRoot.path)
        scheduleReadinessPoll()
    }

    private enum RuntimeState {
        case stopped
        case starting
        case running
        case failed(String)
    }

    private func updateRuntimeState(_ state: RuntimeState) {
        switch state {
        case .stopped:
            primaryButton.configuration?.title = "一键启动酒馆"
            primaryButton.configuration?.image = UIImage(systemName: "play.fill")
            primaryButton.isEnabled = true
            settingsStatusValue.text = "尚未启动"
        case .starting:
            primaryButton.configuration?.title = "小厨正在准备…"
            primaryButton.configuration?.image = nil
            primaryButton.isEnabled = false
            settingsStatusValue.text = "启动中"
        case .running:
            runtimeReady = true
            primaryButton.configuration?.title = "进入酒馆"
            primaryButton.configuration?.image = UIImage(systemName: "arrow.right")
            primaryButton.isEnabled = !tavernEntered
            settingsStatusValue.text = "运行中"
        case .failed(let reason):
            runtimeReady = false
            primaryButton.configuration?.title = "启动失败"
            primaryButton.configuration?.image = nil
            primaryButton.isEnabled = false
            settingsStatusValue.text = "启动失败"
            settingsStatusValue.accessibilityLabel = reason
        }
    }

    private func scheduleReadinessPoll() {
        guard pollAttempts < maximumPollAttempts else {
            updateRuntimeState(.failed("等待 SillyTavern 监听超时。请查看 Xcode 控制台中的 Node 日志。"))
            return
        }
        pollAttempts += 1
        guard let url = URL(string: "http://127.0.0.1:8123/version") else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, response, _ in
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            if statusCode == 200,
               let data,
               String(data: data, encoding: .utf8)?.contains("1.19.0") == true {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.updateRuntimeState(.running)
                    if self.currentTab == 0 { self.enterTavern() }
                }
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.scheduleReadinessPoll()
            }
        }.resume()
    }

    private func enterTavern() {
        guard runtimeReady else { return }
        tavernEntered = true
        if !tavernLoaded {
            tavernLoaded = true
            tavernWebView.load(URLRequest(url: URL(string: "http://127.0.0.1:8123/")!))
        }
        updateRuntimeState(.running)
        refreshNavigation()
    }

    @objc private func copyDataPath() {
        UIPasteboard.general.string = dataRoot.path
        present(ChefDialogController(title: "已复制", message: "存储路径已复制到剪贴板。"), animated: true)
    }

    @objc private func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        present(ChefDialogController(title: "25小厨 Mobile",
            message: "版本 \(version)（\(build)）\nSillyTavern 1.19.0\nNode.js v24.22.1",
            actionTitle: "关闭"), animated: true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === tavernWebView else { return }
        print("[Chef25NodeSpike] SillyTavern page loaded")
        saveUITestSnapshot(named: "chef25-page-loaded.png")
        runAutomationIfRequested()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard webView === tavernWebView else { return }
        print("[Chef25NodeSpike] page load failed: \(error)")
        updateRuntimeState(.failed("SillyTavern 页面加载失败：\(error.localizedDescription)"))
    }

    private func runAutomationIfRequested() {
        guard !automationStarted,
              let message = ProcessInfo.processInfo.environment["CHEF25_UI_TEST_MESSAGE"],
              !message.isEmpty else {
            return
        }
        automationStarted = true

        let apiURL = ProcessInfo.processInfo.environment["CHEF25_UI_TEST_API_URL"] ?? ""
        let model = ProcessInfo.processInfo.environment["CHEF25_UI_TEST_MODEL"] ?? ""
        guard let valuesData = try? JSONSerialization.data(withJSONObject: [message, apiURL, model]),
              let values = String(data: valuesData, encoding: .utf8) else {
            print("[Chef25NodeSpike] could not encode UI test message")
            return
        }

        let script = """
            (() => {
                const [text, apiURL, model] = \(values);
                let attempts = 0;
                const notify = value => {
                    try {
                        window.webkit.messageHandlers.chef25Automation.postMessage(value);
                    } catch {}
                };
                const sendWhenReady = () => {
                    const textarea = document.querySelector('#send_textarea');
                    const sendButton = document.querySelector('#send_but');
                    if (!textarea || !sendButton || sendButton.classList.contains('displayNone')) {
                        attempts += 1;
                        if (attempts < 80) {
                            setTimeout(sendWhenReady, 250);
                        }
                        return;
                    }
                    textarea.focus();
                    textarea.value = text;
                    textarea.dispatchEvent(new InputEvent('input', {
                        bubbles: true,
                        inputType: 'insertText',
                        data: text,
                    }));
                    setTimeout(() => {
                        sendButton.click();
                        notify('message submitted: ' + text);
                        setTimeout(() => notify('request-snapshot'), 5000);
                    }, 250);
                };
                const configureAndSend = () => {
                    if (!window.jQuery) {
                        setTimeout(configureAndSend, 250);
                        return;
                    }
                    if (apiURL) {
                        window.jQuery('#main_api').val('openai').trigger('change');
                        window.jQuery('#chat_completion_source').val('custom').trigger('change');
                        window.jQuery('#custom_api_url_text').val(apiURL).trigger('input');
                        window.jQuery('#custom_model_id').val(model || 'chef25-local-fake').trigger('input');
                        window.jQuery('#api_key_custom').val('').trigger('input');
                        notify('custom API configured: ' + apiURL + ' / ' + (model || 'chef25-local-fake'));
                        setTimeout(sendWhenReady, 1500);
                    } else {
                        sendWhenReady();
                    }
                };
                setTimeout(configureAndSend, 1500);
            })();
            """

        tavernWebView.evaluateJavaScript(script) { _, error in
            if let error {
                print("[Chef25NodeSpike] UI automation failed: \(error)")
            } else {
                print("[Chef25NodeSpike] UI automation started")
            }
        }
    }

    @objc private func applicationDidBecomeActive() {
        refreshMascotMotion()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.saveUITestSnapshot(named: "chef25-foreground-recovery.png")
        }
    }

    private func saveUITestSnapshot(named filename: String) {
        guard view.bounds.width > 0, view.bounds.height > 0 else {
            print("[Chef25NodeSpike] screenshot skipped: view has no size")
            return
        }
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
        let image = renderer.image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        guard let data = image.pngData() else {
            print("[Chef25NodeSpike] screenshot failed: could not encode PNG")
            return
        }
        let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
        let destination = documents.appendingPathComponent(filename)
        do {
            try data.write(to: destination, options: .atomic)
            print("[Chef25NodeSpike] screenshot saved: \(filename)")
        } catch {
            print("[Chef25NodeSpike] screenshot write failed: \(error)")
        }
    }
}

private final class BrandMarkView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
        accessibilityElementsHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        context.translateBy(x: rect.midX, y: rect.midY)
        context.rotate(by: -.pi / 36)
        context.translateBy(x: -rect.midX, y: -rect.midY)

        UIColor(red: 0.922, green: 0.376, blue: 0.239, alpha: 1).setFill()
        UIBezierPath(
            roundedRect: rect,
            cornerRadius: rect.width * (12 / 38)
        ).fill()

        let iconSize = rect.width * (25 / 38)
        let scale = iconSize / 24
        let offset = CGPoint(
            x: (rect.width - iconSize) / 2,
            y: (rect.height - iconSize) / 2
        )
        let hat = UIBezierPath()
        hat.move(to: CGPoint(x: 17 * scale + offset.x, y: 21 * scale + offset.y))
        hat.addCurve(
            to: CGPoint(x: 18 * scale + offset.x, y: 15 * scale + offset.y),
            controlPoint1: CGPoint(x: 17.6 * scale + offset.x, y: 20.2 * scale + offset.y),
            controlPoint2: CGPoint(x: 18 * scale + offset.x, y: 17 * scale + offset.y)
        )
        hat.addCurve(
            to: CGPoint(x: 18.8 * scale + offset.x, y: 13.9 * scale + offset.y),
            controlPoint1: CGPoint(x: 18 * scale + offset.x, y: 14.6 * scale + offset.y),
            controlPoint2: CGPoint(x: 18.4 * scale + offset.x, y: 14.2 * scale + offset.y)
        )
        hat.addCurve(
            to: CGPoint(x: 16.7 * scale + offset.x, y: 6.3 * scale + offset.y),
            controlPoint1: CGPoint(x: 21.7 * scale + offset.x, y: 10.8 * scale + offset.y),
            controlPoint2: CGPoint(x: 20.2 * scale + offset.x, y: 6.3 * scale + offset.y)
        )
        hat.addCurve(
            to: CGPoint(x: 7.5 * scale + offset.x, y: 6.3 * scale + offset.y),
            controlPoint1: CGPoint(x: 14.2 * scale + offset.x, y: 2.3 * scale + offset.y),
            controlPoint2: CGPoint(x: 9.8 * scale + offset.x, y: 2.3 * scale + offset.y)
        )
        hat.addCurve(
            to: CGPoint(x: 5.3 * scale + offset.x, y: 13.9 * scale + offset.y),
            controlPoint1: CGPoint(x: 3.5 * scale + offset.x, y: 6.3 * scale + offset.y),
            controlPoint2: CGPoint(x: 2.2 * scale + offset.x, y: 10.8 * scale + offset.y)
        )
        hat.addCurve(
            to: CGPoint(x: 6 * scale + offset.x, y: 15 * scale + offset.y),
            controlPoint1: CGPoint(x: 5.7 * scale + offset.x, y: 14.2 * scale + offset.y),
            controlPoint2: CGPoint(x: 6 * scale + offset.x, y: 14.6 * scale + offset.y)
        )
        hat.addLine(to: CGPoint(x: 6 * scale + offset.x, y: 20 * scale + offset.y))
        hat.addCurve(
            to: CGPoint(x: 7 * scale + offset.x, y: 21 * scale + offset.y),
            controlPoint1: CGPoint(x: 6 * scale + offset.x, y: 20.6 * scale + offset.y),
            controlPoint2: CGPoint(x: 6.4 * scale + offset.x, y: 21 * scale + offset.y)
        )
        hat.close()

        UIColor(red: 1, green: 0.976, blue: 0.933, alpha: 1).setStroke()
        hat.lineWidth = max(1.5, rect.width * 0.07)
        hat.lineCapStyle = .round
        hat.lineJoinStyle = .round
        hat.stroke()

        let band = UIBezierPath()
        band.move(to: CGPoint(x: 6 * scale + offset.x, y: 17 * scale + offset.y))
        band.addLine(to: CGPoint(x: 18 * scale + offset.x, y: 17 * scale + offset.y))
        band.lineWidth = hat.lineWidth
        band.lineCapStyle = .round
        band.stroke()
        context.restoreGState()
    }
}

private final class TavernBrandView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
        accessibilityLabel = "基于 SillyTavern"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 108, height: 18)
    }

    override func draw(_ rect: CGRect) {
        let caption = "基于" as NSString
        let name = "SillyTavern" as NSString
        let captionAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9),
            .foregroundColor: UIColor(red: 0.518, green: 0.514, blue: 0.471, alpha: 1),
        ]
        let nameAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10.5, weight: .bold),
            .foregroundColor: UIColor(red: 0.925, green: 0.396, blue: 0.255, alpha: 1),
        ]
        let captionSize = caption.size(withAttributes: captionAttributes)
        let nameSize = name.size(withAttributes: nameAttributes)
        let gap: CGFloat = 5
        let totalWidth = captionSize.width + gap + nameSize.width
        let originX = rect.maxX - totalWidth
        caption.draw(at: CGPoint(x: originX, y: 3), withAttributes: captionAttributes)
        let nameOrigin = CGPoint(x: originX + captionSize.width + gap, y: 0)
        name.draw(at: nameOrigin, withAttributes: nameAttributes)

        let underline = UIBezierPath()
        underline.move(to: CGPoint(x: nameOrigin.x - 1, y: 14.5))
        underline.addCurve(
            to: CGPoint(x: nameOrigin.x + nameSize.width + 1, y: 14),
            controlPoint1: CGPoint(x: nameOrigin.x + nameSize.width * 0.35, y: 12.5),
            controlPoint2: CGPoint(x: nameOrigin.x + nameSize.width * 0.7, y: 13)
        )
        underline.move(to: CGPoint(x: nameOrigin.x + 2, y: 17))
        underline.addCurve(
            to: CGPoint(x: nameOrigin.x + nameSize.width - 2, y: 16.5),
            controlPoint1: CGPoint(x: nameOrigin.x + nameSize.width * 0.35, y: 14.8),
            controlPoint2: CGPoint(x: nameOrigin.x + nameSize.width * 0.72, y: 15.2)
        )
        UIColor(red: 0.961, green: 0.678, blue: 0.573, alpha: 1).setStroke()
        underline.lineWidth = 1
        underline.lineCapStyle = .round
        underline.stroke()
    }
}

private final class ChefMascotView: UIView {
    private var displayLink: CADisplayLink?
    private var motionTime: TimeInterval = 0
    private var previousFrame: TimeInterval = 0

    func setAnimating(_ active: Bool) {
        guard active != (displayLink != nil) else { return }
        if active {
            previousFrame = 0
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.preferredFramesPerSecond = 30
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else {
            displayLink?.invalidate()
            displayLink = nil
            setNeedsDisplay()
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        if previousFrame > 0 {
            motionTime += min(link.timestamp - previousFrame, 0.1)
        }
        previousFrame = link.timestamp
        setNeedsDisplay()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        let pose = UIAccessibility.isReduceMotionEnabled ? MascotPose() : MascotPose.at(motionTime)
        let lookX = CGFloat(pose.lookX)
        let lookY = CGFloat(pose.lookY)
        let joy = CGFloat(pose.joy)
        let eyeOpen = CGFloat(pose.eyeOpen)
        let scale = min(rect.width / 200, rect.height / 150)
        let origin = CGPoint(
            x: (rect.width - 200 * scale) / 2,
            y: (rect.height - 150 * scale) / 2
        )
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
        }

        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                UIColor(red: 0.961, green: 0.925, blue: 0.855, alpha: 1).cgColor,
                UIColor(red: 0.961, green: 0.925, blue: 0.855, alpha: 1).cgColor,
                UIColor(red: 0.961, green: 0.925, blue: 0.855, alpha: 0).cgColor,
            ] as CFArray,
            locations: [0, 0.05, 0.68]
        ) {
            let context = UIGraphicsGetCurrentContext()
            context?.saveGState()
            context?.translateBy(x: rect.midX, y: rect.midY)
            context?.scaleBy(x: 1, y: 0.75)
            context?.drawRadialGradient(
                gradient,
                startCenter: .zero,
                startRadius: 0,
                endCenter: .zero,
                endRadius: rect.width / 2,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
            context?.restoreGState()
        }

        UIColor(red: 0.914, green: 0.863, blue: 0.765, alpha: 0.65).setFill()
        UIBezierPath(ovalIn: CGRect(
            x: point(56, 129).x,
            y: point(56, 129).y,
            width: 88 * scale,
            height: 10 * scale
        )).fill()

        func sparkle(_ x: CGFloat, _ y: CGFloat, size: CGFloat, filled: Bool) {
            let path = UIBezierPath()
            path.move(to: point(x, y - size))
            path.addQuadCurve(to: point(x + size, y), controlPoint: point(x, y))
            path.addQuadCurve(to: point(x, y + size), controlPoint: point(x, y))
            path.addQuadCurve(to: point(x - size, y), controlPoint: point(x, y))
            path.addQuadCurve(to: point(x, y - size), controlPoint: point(x, y))
            if filled {
                UIColor(red: 0.839, green: 0.706, blue: 0.435, alpha: 1).setFill()
                path.fill()
            } else {
                UIColor(red: 0.839, green: 0.706, blue: 0.435, alpha: 1).setStroke()
                path.lineWidth = 1.3 * scale
                path.stroke()
            }
        }
        sparkle(27, 58, size: 10, filled: true)
        sparkle(172, 110, size: 8, filled: false)

        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        context?.translateBy(x: point(100, 82).x + CGFloat(pose.headX) * 2.5 * scale,
            y: point(100, 82).y + CGFloat(pose.headY) * scale - CGFloat(pose.bob) * scale)
        context?.rotate(by: CGFloat(pose.headX) * 0.04)
        context?.translateBy(x: -point(100, 82).x, y: -point(100, 82).y)
        let hat = UIBezierPath()
        hat.move(to: point(67, 87))
        hat.addCurve(to: point(70, 46), controlPoint1: point(43, 79), controlPoint2: point(45, 47))
        hat.addCurve(to: point(124, 46), controlPoint1: point(81, 19), controlPoint2: point(112, 19))
        hat.addCurve(to: point(134, 88), controlPoint1: point(151, 44), controlPoint2: point(158, 77))
        hat.addLine(to: point(134, 117))
        hat.addQuadCurve(to: point(129, 122), controlPoint: point(134, 122))
        hat.addLine(to: point(72, 122))
        hat.addQuadCurve(to: point(67, 117), controlPoint: point(67, 122))
        hat.close()
        UIColor(red: 1, green: 0.941, blue: 0.839, alpha: 1).setFill()
        hat.fill()
        UIColor(red: 0.8, green: 0.545, blue: 0.314, alpha: 1).setStroke()
        hat.lineWidth = 5 * scale
        hat.lineJoinStyle = .round
        hat.stroke()

        let band = UIBezierPath()
        band.move(to: point(69, 105))
        band.addLine(to: point(132, 105))
        band.lineWidth = 4 * scale
        band.lineCapStyle = .round
        band.stroke()

        context?.translateBy(x: lookX * 5 * scale, y: lookY * 3 * scale)
        UIColor(red: 0.918, green: 0.643, blue: 0.529, alpha: 0.15 + joy * 0.45).setFill()
        UIBezierPath(ovalIn: CGRect(
            x: point(70, 89).x,
            y: point(89, 89).y,
            width: 12 * scale,
            height: 6 * scale
        )).fill()
        UIBezierPath(ovalIn: CGRect(
            x: point(118, 89).x,
            y: point(89, 89).y,
            width: 12 * scale,
            height: 6 * scale
        )).fill()

        let eyeColor = UIColor(red: 0.569, green: 0.420, blue: 0.286, alpha: 1)
        eyeColor.setFill()
        eyeColor.setStroke()
        for eyeX: CGFloat in [85, 115] {
            if eyeOpen <= 0.001 || pose.smilingEyes {
                // Preserve a visible stroke when closed. Both expressions meet
                // at exactly the same closed-eye line, with no curve inversion.
                let eye = UIBezierPath()
                eye.move(to: point(eyeX - 3, 82 + eyeOpen))
                eye.addQuadCurve(to: point(eyeX + 3, 82 + eyeOpen),
                    controlPoint: point(eyeX, 82 - eyeOpen * 5))
                eye.lineWidth = CGFloat(pose.eyeLineWidth) * scale
                eye.lineCapStyle = .round
                eye.stroke()
            } else {
                let width = CGFloat(pose.eyeWidth) * scale
                let height = CGFloat(pose.eyeHeight) * scale
                let center = point(eyeX, 82)
                UIBezierPath(ovalIn: CGRect(x: center.x - width / 2, y: center.y - height / 2,
                    width: width, height: height)).fill()
            }
        }
        let mouth = UIBezierPath()
        mouth.move(to: point(96, 91))
        mouth.addQuadCurve(to: point(104, 91), controlPoint: point(100, 98 + joy * 3))
        mouth.lineWidth = 2.5 * scale
        mouth.lineCapStyle = .round
        mouth.stroke()
        context?.restoreGState()
    }
}

extension RuntimeViewController: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "chef25Automation" else { return }
        print("[Chef25NodeSpike] automation: \(message.body)")
        if message.body as? String == "request-snapshot" {
            saveUITestSnapshot(named: "chef25-shell-tavern-reply.png")
        }
    }
}


// App-owned modal and controls; never use the platform alert appearance.
private final class ChefDialogController: UIViewController {
    private let heading: String
    private let message: String
    private let phrase: String?
    private let actionTitle: String
    private let onConfirm: (() -> Void)?
    private let field = ChefTextField()
    private let confirmButton = ChefActionButton(primary: true)

    init(title: String, message: String, phrase: String? = nil,
         actionTitle: String = "知道了", onConfirm: (() -> Void)? = nil) {
        heading = title
        self.message = message
        self.phrase = phrase
        self.actionTitle = actionTitle
        self.onConfirm = onConfirm
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.38)
        view.accessibilityViewIsModal = true
        let card = UIView()
        card.backgroundColor = UIColor(red: 1, green: 0.992, blue: 0.976, alpha: 1)
        card.layer.cornerRadius = 20
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor(red: 0.902, green: 0.890, blue: 0.851, alpha: 1).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(scroll)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        let title = UILabel()
        title.text = heading
        title.font = .systemFont(ofSize: 20, weight: .bold)
        title.textColor = UIColor(red: 0.188, green: 0.200, blue: 0.173, alpha: 1)
        title.numberOfLines = 0
        title.accessibilityTraits = .header
        stack.addArrangedSubview(title)
        let body = UILabel()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        body.attributedText = NSAttributedString(string: message, attributes: [.paragraphStyle: paragraph])
        body.font = .systemFont(ofSize: 14)
        body.textColor = UIColor(red: 0.455, green: 0.471, blue: 0.412, alpha: 1)
        body.numberOfLines = 0
        stack.addArrangedSubview(body)
        if let phrase {
            field.placeholder = "请输入：" + phrase
            field.accessibilityLabel = "输入" + phrase
            field.addTarget(self, action: #selector(phraseChanged), for: .editingChanged)
            stack.addArrangedSubview(field)
            field.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        }
        let actions = UIStackView()
        actions.axis = .horizontal
        actions.spacing = 10
        actions.distribution = .fillEqually
        if phrase != nil {
            let cancel = ChefActionButton(primary: false)
            cancel.setTitle("取消", for: .normal)
            cancel.addTarget(self, action: #selector(close), for: .touchUpInside)
            actions.addArrangedSubview(cancel)
        }
        confirmButton.setTitle(actionTitle, for: .normal)
        confirmButton.isEnabled = phrase == nil
        confirmButton.addTarget(self, action: #selector(confirm), for: .touchUpInside)
        actions.addArrangedSubview(confirmButton)
        stack.addArrangedSubview(actions)
        stack.setCustomSpacing(24, after: stack.arrangedSubviews[stack.arrangedSubviews.count - 2])
        actions.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        let naturalHeight = scroll.heightAnchor.constraint(equalTo: stack.heightAnchor)
        naturalHeight.priority = .defaultHigh
        let centered = card.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor)
        centered.priority = .defaultHigh
        let width = card.widthAnchor.constraint(equalToConstant: 360)
        width.priority = .defaultHigh
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor), centered, width,
            card.widthAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.widthAnchor, constant: -40),
            card.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            card.bottomAnchor.constraint(lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            scroll.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24),
            scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor), naturalHeight,
        ])
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIAccessibility.post(notification: .screenChanged, argument: view)
    }
    @objc private func phraseChanged() { confirmButton.isEnabled = field.text == phrase }
    @objc private func close() { dismiss(animated: true) }
    @objc private func confirm() {
        guard phrase == nil || field.text == phrase else { return }
        let callback = onConfirm
        dismiss(animated: true) { callback?() }
    }
    override func accessibilityPerformEscape() -> Bool { close(); return true }
}

private final class ChefActionButton: UIButton {
    private let primary: Bool
    init(primary: Bool) {
        self.primary = primary
        super.init(frame: .zero)
        titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel?.adjustsFontSizeToFitWidth = true
        titleLabel?.minimumScaleFactor = 0.8
        layer.cornerRadius = 10
        layer.borderWidth = 1
        layer.borderColor = UIColor(red: 0.902, green: 0.890, blue: 0.851, alpha: 1).cgColor
        setTitleColor(primary ? .white : UIColor(red: 0.188, green: 0.200, blue: 0.173, alpha: 1), for: .normal)
        refreshAppearance()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isEnabled: Bool { didSet { refreshAppearance() } }
    override var isHighlighted: Bool { didSet { refreshAppearance() } }
    private func refreshAppearance() {
        backgroundColor = primary ? UIColor(red: 0.925, green: 0.396, blue: 0.255, alpha: 1)
            : UIColor(red: 0.953, green: 0.945, blue: 0.914, alpha: 1)
        alpha = !isEnabled ? 0.38 : (isHighlighted ? 0.75 : 1)
    }
}

private final class ChefTextField: UITextField {
    init() {
        super.init(frame: .zero)
        borderStyle = .none
        backgroundColor = UIColor(red: 0.984, green: 0.976, blue: 0.961, alpha: 1)
        textColor = UIColor(red: 0.188, green: 0.200, blue: 0.173, alpha: 1)
        tintColor = UIColor(red: 0.925, green: 0.396, blue: 0.255, alpha: 1)
        font = .systemFont(ofSize: 14)
        autocorrectionType = .no
        layer.cornerRadius = 10
        layer.borderWidth = 1
        layer.borderColor = UIColor(red: 0.839, green: 0.824, blue: 0.773, alpha: 1).cgColor
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func textRect(forBounds bounds: CGRect) -> CGRect { bounds.insetBy(dx: 14, dy: 12) }
    override func editingRect(forBounds bounds: CGRect) -> CGRect { textRect(forBounds: bounds) }
    override func placeholderRect(forBounds bounds: CGRect) -> CGRect { textRect(forBounds: bounds) }
}
