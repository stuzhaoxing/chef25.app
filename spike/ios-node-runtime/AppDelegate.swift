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

final class RuntimeViewController: UIViewController, WKNavigationDelegate {
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

    private let header = UIView()
    private let contentContainer = UIView()
    private let tabBar = UIStackView()
    private let homeButton = UIButton(type: .system)
    private let pageTitle = UILabel()
    private let pageSubtitle = TavernBrandView()

    private let launcherScroll = UIScrollView()
    private let dataScroll = UIScrollView()
    private let settingsScroll = UIScrollView()
    private let docsWebView = WKWebView(frame: .zero)
    private let tavernWebView = WKWebView(frame: .zero)

    private let statusCard = UIView()
    private let statusDot = UIView()
    private let statusTitle = UILabel()
    private let primaryButton = UIButton(type: .system)
    private let settingsRuntimeValue = UILabel()
    private let settingsStatusValue = UILabel()

    private var tabButtons: [UIButton] = []
    private var contentTopWithHeader: NSLayoutConstraint!
    private var contentTopFull: NSLayoutConstraint!
    private var contentBottomWithTabs: NSLayoutConstraint!
    private var contentBottomFull: NSLayoutConstraint!
    private var tabHeightConstraint: NSLayoutConstraint!
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
        configureHeader()
        configureTabBar()
        configureContent()
        configureLauncher()
        configureDataPage()
        configureSettingsPage()
        configureWebViews()
        refreshNavigation()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        if ProcessInfo.processInfo.environment["CHEF25_AUTO_START"] == "1"
            || ProcessInfo.processInfo.environment["CHEF25_UI_TEST_MESSAGE"] != nil {
            startRuntime()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configureHeader() {
        header.translatesAutoresizingMaskIntoConstraints = false
        header.backgroundColor = Palette.sidebar
        view.addSubview(header)

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

        let aboutButton = UIButton(type: .system)
        aboutButton.translatesAutoresizingMaskIntoConstraints = false
        aboutButton.setImage(UIImage(systemName: "info.circle"), for: .normal)
        aboutButton.tintColor = Palette.muted
        aboutButton.accessibilityLabel = "关于"
        aboutButton.addTarget(self, action: #selector(showAbout), for: .touchUpInside)
        header.addSubview(aboutButton)

        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = Palette.line
        header.addSubview(divider)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 64),

            brandMark.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 18),
            brandMark.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            brandMark.widthAnchor.constraint(equalToConstant: 36),
            brandMark.heightAnchor.constraint(equalToConstant: 36),

            brandCopy.leadingAnchor.constraint(equalTo: brandMark.trailingAnchor, constant: 10),
            brandCopy.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            aboutButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -14),
            aboutButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            aboutButton.widthAnchor.constraint(equalToConstant: 36),
            aboutButton.heightAnchor.constraint(equalToConstant: 36),

            pageCopy.trailingAnchor.constraint(equalTo: aboutButton.leadingAnchor, constant: -8),
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
        view.addSubview(contentContainer)
        contentTopWithHeader = contentContainer.topAnchor.constraint(equalTo: header.bottomAnchor)
        contentTopFull = contentContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        contentBottomWithTabs = contentContainer.bottomAnchor.constraint(equalTo: tabBar.topAnchor)
        contentBottomFull = contentContainer.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor
        )
        NSLayoutConstraint.activate([
            contentTopWithHeader,
            contentBottomWithTabs,
            contentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
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

        homeButton.translatesAutoresizingMaskIntoConstraints = false
        var homeConfiguration = UIButton.Configuration.filled()
        homeConfiguration.title = "小厨"
        homeConfiguration.image = UIImage(systemName: "chevron.left")
        homeConfiguration.imagePlacement = .leading
        homeConfiguration.imagePadding = 2
        homeConfiguration.baseForegroundColor = Palette.accent
        homeConfiguration.baseBackgroundColor = UIColor(white: 0.09, alpha: 0.86)
        homeConfiguration.cornerStyle = .capsule
        homeConfiguration.contentInsets = NSDirectionalEdgeInsets(
            top: 6,
            leading: 8,
            bottom: 6,
            trailing: 9
        )
        homeButton.configuration = homeConfiguration
        homeButton.accessibilityLabel = "返回小厨"
        homeButton.addTarget(self, action: #selector(returnToLauncher), for: .touchUpInside)
        homeButton.isHidden = true
        contentContainer.addSubview(homeButton)
        NSLayoutConstraint.activate([
            homeButton.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -8),
            homeButton.centerYAnchor.constraint(equalTo: contentContainer.centerYAnchor),
            homeButton.heightAnchor.constraint(equalToConstant: 34),
        ])
    }

    private func configureTabBar() {
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        tabBar.axis = .horizontal
        tabBar.distribution = .fillEqually
        tabBar.alignment = .fill
        tabBar.backgroundColor = Palette.sidebar
        view.addSubview(tabBar)

        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = Palette.line
        view.addSubview(divider)

        let tabs: [(String, String)] = [
            ("我的酒馆", "cup.and.saucer.fill"),
            ("本地数据", "folder.fill"),
            ("中文文档", "questionmark.circle.fill"),
            ("设置", "gearshape.fill"),
        ]
        for (index, tab) in tabs.enumerated() {
            var configuration = UIButton.Configuration.plain()
            configuration.title = tab.0
            configuration.image = UIImage(systemName: tab.1)
            configuration.imagePlacement = .top
            configuration.imagePadding = 3
            configuration.baseForegroundColor = Palette.muted
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 4, bottom: 6, trailing: 4)
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
                var attributes = $0
                attributes.font = .systemFont(ofSize: 10, weight: .medium)
                return attributes
            }
            let button = UIButton(configuration: configuration)
            button.tag = index
            button.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
            tabBar.addArrangedSubview(button)
            tabButtons.append(button)
        }

        tabHeightConstraint = tabBar.heightAnchor.constraint(equalToConstant: 58)
        NSLayoutConstraint.activate([
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            divider.topAnchor.constraint(equalTo: tabBar.topAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),

            tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            tabHeightConstraint,
        ])
    }

    private func configureLauncher() {
        launcherScroll.alwaysBounceVertical = true
        launcherScroll.showsVerticalScrollIndicator = false

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 12
        launcherScroll.addSubview(stack)

        let hero = UIView()
        let heroStack = UIStackView()
        heroStack.translatesAutoresizingMaskIntoConstraints = false
        heroStack.axis = .vertical
        heroStack.alignment = .center
        heroStack.spacing = 6
        hero.addSubview(heroStack)

        let mascot = ChefMascotView()
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
        var primaryConfiguration = UIButton.Configuration.filled()
        primaryConfiguration.title = "一键启动酒馆"
        primaryConfiguration.image = UIImage(systemName: "play.fill")
        primaryConfiguration.imagePadding = 9
        primaryConfiguration.baseBackgroundColor = Palette.accent
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

        configureStatusCard()
        stack.addArrangedSubview(statusCard)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: launcherScroll.contentLayoutGuide.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: launcherScroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: launcherScroll.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: launcherScroll.frameLayoutGuide.trailingAnchor, constant: -20),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 620),
            stack.centerXAnchor.constraint(equalTo: launcherScroll.frameLayoutGuide.centerXAnchor),
        ])
    }

    private func configureStatusCard() {
        statusCard.translatesAutoresizingMaskIntoConstraints = false
        statusCard.backgroundColor = .clear

        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusDot.backgroundColor = UIColor(red: 0.690, green: 0.706, blue: 0.647, alpha: 1)
        statusDot.layer.cornerRadius = 4
        statusCard.addSubview(statusDot)

        statusTitle.translatesAutoresizingMaskIntoConstraints = false
        statusTitle.text = "酒馆尚未启动"
        statusTitle.textColor = Palette.muted
        statusTitle.font = .systemFont(ofSize: 11, weight: .regular)
        statusTitle.textAlignment = .center
        statusCard.addSubview(statusTitle)

        NSLayoutConstraint.activate([
            statusCard.heightAnchor.constraint(equalToConstant: 22),
            statusTitle.centerXAnchor.constraint(equalTo: statusCard.centerXAnchor),
            statusTitle.centerYAnchor.constraint(equalTo: statusCard.centerYAnchor),
            statusDot.trailingAnchor.constraint(equalTo: statusTitle.leadingAnchor, constant: -7),
            statusDot.centerYAnchor.constraint(equalTo: statusTitle.centerYAnchor),
            statusDot.widthAnchor.constraint(equalToConstant: 6),
            statusDot.heightAnchor.constraint(equalToConstant: 6),
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
        var configuration = UIButton.Configuration.tinted()
        configuration.title = title
        configuration.image = UIImage(systemName: image)
        configuration.imagePadding = 7
        configuration.baseForegroundColor = Palette.ink
        configuration.baseBackgroundColor = Palette.sidebar
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
    }

    private func setTab(_ index: Int) {
        guard (0..<tabButtons.count).contains(index) else { return }
        currentTab = index
        if index == 2 && !docsLoaded {
            docsLoaded = true
            docsWebView.load(URLRequest(url: URL(string: "https://www.chef25.com/guides/sillytavern/")!))
        }
        refreshNavigation()
    }

    private func refreshNavigation() {
        let inTavern = currentTab == 0 && tavernEntered
        header.isHidden = inTavern
        tabBar.isHidden = inTavern
        launcherScroll.isHidden = currentTab != 0 || tavernEntered
        dataScroll.isHidden = currentTab != 1
        docsWebView.isHidden = currentTab != 2
        settingsScroll.isHidden = currentTab != 3
        tavernWebView.isHidden = !inTavern
        homeButton.isHidden = !inTavern
        contentTopWithHeader.isActive = !inTavern
        contentTopFull.isActive = inTavern
        contentBottomWithTabs.isActive = !inTavern
        contentBottomFull.isActive = inTavern
        view.backgroundColor = inTavern ? UIColor(white: 0.09, alpha: 1) : Palette.paper
        contentContainer.backgroundColor = inTavern ? UIColor(white: 0.09, alpha: 1) : .clear
        tavernWebView.scrollView.contentInsetAdjustmentBehavior = .never
        setNeedsStatusBarAppearanceUpdate()

        let titles = ["我的酒馆", "本地数据", "中文文档", "设置"]
        pageTitle.text = titles[min(currentTab, titles.count - 1)]
        pageSubtitle.isHidden = currentTab != 0
        for (index, button) in tabButtons.enumerated() {
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
            statusDot.backgroundColor = UIColor(red: 0.690, green: 0.706, blue: 0.647, alpha: 1)
            statusTitle.text = "酒馆尚未启动"
            primaryButton.configuration?.title = "一键启动酒馆"
            primaryButton.configuration?.image = UIImage(systemName: "play.fill")
            primaryButton.isEnabled = true
            settingsStatusValue.text = "尚未启动"
        case .starting:
            statusDot.backgroundColor = Palette.amber
            statusTitle.text = "酒馆准备中…"
            primaryButton.configuration?.title = "小厨正在准备…"
            primaryButton.configuration?.image = nil
            primaryButton.isEnabled = false
            settingsStatusValue.text = "启动中"
        case .running:
            runtimeReady = true
            statusDot.backgroundColor = Palette.green
            statusTitle.text = "酒馆运行中"
            primaryButton.configuration?.title = "进入酒馆"
            primaryButton.configuration?.image = UIImage(systemName: "arrow.right")
            primaryButton.isEnabled = !tavernEntered
            settingsStatusValue.text = "运行中"
        case .failed(let reason):
            runtimeReady = false
            statusDot.backgroundColor = UIColor(red: 0.745, green: 0.275, blue: 0.220, alpha: 1)
            statusTitle.text = "启动失败"
            statusTitle.accessibilityLabel = reason
            primaryButton.configuration?.title = "启动失败"
            primaryButton.configuration?.image = nil
            primaryButton.isEnabled = false
            settingsStatusValue.text = "启动失败"
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
                    if ProcessInfo.processInfo.environment["CHEF25_UI_TEST_MESSAGE"] != nil {
                        self.enterTavern()
                    }
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
        let alert = UIAlertController(title: "已复制", message: "存储路径已复制到剪贴板。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }

    @objc private func showAbout() {
        let alert = UIAlertController(
            title: "25小厨 Mobile",
            message: """
            SillyTavern 1.19.0
            Node.js v24.22.1
            """,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "关闭", style: .default))
        present(alert, animated: true)
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

        UIColor(red: 0.918, green: 0.643, blue: 0.529, alpha: 0.24).setFill()
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

        UIColor(red: 0.569, green: 0.420, blue: 0.286, alpha: 1).setStroke()
        for eyeX in [85.0, 115.0] {
            let eye = UIBezierPath()
            eye.move(to: point(eyeX, 81))
            eye.addQuadCurve(to: point(eyeX, 81), controlPoint: point(eyeX, 85.5))
            eye.lineWidth = 4.5 * scale
            eye.lineCapStyle = .round
            eye.stroke()
        }
        let mouth = UIBezierPath()
        mouth.move(to: point(96, 91))
        mouth.addQuadCurve(to: point(104, 91), controlPoint: point(100, 97))
        mouth.lineWidth = 2.5 * scale
        mouth.lineCapStyle = .round
        mouth.stroke()
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
