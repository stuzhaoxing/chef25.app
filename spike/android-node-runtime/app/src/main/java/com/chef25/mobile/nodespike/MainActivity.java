package com.chef25.mobile.nodespike;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RadialGradient;
import android.graphics.RectF;
import android.graphics.Shader;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsetsController;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import org.json.JSONArray;

import java.io.BufferedInputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

public final class MainActivity extends Activity {
    private static final String TAG = "Chef25NodeSpike";
    private static final String RUNTIME_ZIP = "nodejs-project.zip";
    private static final String RUNTIME_MARKER = "chef25-runtime-version.txt";
    private static final String RUNTIME_VERSION =
        "SillyTavern-1.19.0-nodejs-24.22.1-chef25-runtime-v3";
    private static final int PAPER = Color.rgb(251, 249, 245);
    private static final int SIDEBAR = Color.rgb(243, 241, 233);
    private static final int INK = Color.rgb(48, 51, 44);
    private static final int MUTED = Color.rgb(132, 135, 121);
    private static final int ACCENT = Color.rgb(235, 96, 61);
    private static final int PRIMARY = Color.rgb(236, 101, 65);
    private static final int SELECTED = Color.rgb(207, 101, 63);
    private static final int ACCENT_SOFT = Color.rgb(248, 229, 216);
    private static final int LINE = Color.rgb(230, 227, 217);
    private static final int CARD = Color.rgb(255, 253, 249);
    private static final int GREEN = Color.rgb(34, 164, 71);
    private static final int AMBER = Color.rgb(216, 155, 77);
    private static final int ERROR = Color.rgb(180, 61, 50);

    static {
        System.loadLibrary("native-lib");
        System.loadLibrary("node");
    }

    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService startupExecutor = Executors.newSingleThreadExecutor();
    private LinearLayout root;
    private View header;
    private FrameLayout content;
    private LinearLayout tabBar;
    private TextView homeButton;
    private TextView pageTitle;
    private TavernBrandView pageSubtitle;
    private ScrollView launcherPage;
    private ScrollView dataPage;
    private ScrollView settingsPage;
    private WebView docsWebView;
    private WebView tavernWebView;
    private TextView statusDot;
    private TextView statusTitle;
    private TextView settingsStatus;
    private Button primaryButton;
    private TextView[] tabViews = new TextView[4];
    private NavIconView[] tabIcons = new NavIconView[4];
    private File projectDirectory;
    private File dataDirectory;
    private int currentTab;
    private int readinessAttempts;
    private boolean runtimeStarted;
    private boolean runtimeReady;
    private boolean tavernLoaded;
    private boolean tavernEntered;
    private boolean docsLoaded;
    private boolean automationStarted;
    private int safeTop;
    private int safeBottom;

    private native int startNodeWithArguments(String[] arguments, String nodePath);

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        configureViews();
        configureSystemBars();
        showTab(0);
        if (getIntent().getStringExtra("CHEF25_UI_TEST_MESSAGE") != null) {
            startRuntime();
        }
    }

    private void configureSystemBars() {
        boolean dark = tavernEntered;
        getWindow().setStatusBarColor(Color.TRANSPARENT);
        getWindow().setNavigationBarColor(dark ? Color.rgb(23, 23, 23) : PAPER);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            WindowInsetsController controller = getWindow().getInsetsController();
            if (controller != null) {
                int light = WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS
                    | WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS;
                controller.setSystemBarsAppearance(dark ? 0 : light, light);
            }
        } else {
            int flags = dark ? 0 : View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR;
            if (!dark && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                flags |= View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR;
            }
            getWindow().getDecorView().setSystemUiVisibility(flags);
        }
    }

    @Override
    public void onBackPressed() {
        if (tavernEntered) {
            tavernEntered = false;
            refreshNavigation();
            updateRuntimeState(RuntimeState.RUNNING);
            return;
        }
        if (currentTab != 0) {
            showTab(0);
            return;
        }
        super.onBackPressed();
    }

    @Override
    protected void onDestroy() {
        startupExecutor.shutdownNow();
        if (tavernWebView != null) {
            tavernWebView.destroy();
        }
        if (docsWebView != null) {
            docsWebView.destroy();
        }
        super.onDestroy();
    }

    private void configureViews() {
        root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(PAPER);
        root.setOnApplyWindowInsetsListener((view, insets) -> {
            safeTop = insets.getSystemWindowInsetTop();
            safeBottom = insets.getSystemWindowInsetBottom();
            applyShellLayout();
            return insets;
        });

        header = createHeader();
        root.addView(header, new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            dp(64)
        ));

        content = new FrameLayout(this);
        root.addView(content, new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            0,
            1
        ));

        tabBar = createTabBar();
        root.addView(tabBar, new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            dp(58)
        ));
        setContentView(root);

        launcherPage = createLauncherPage();
        dataPage = createDataPage();
        settingsPage = createSettingsPage();
        tavernWebView = createRuntimeWebView();
        docsWebView = createDocsWebView();

        addContentPage(launcherPage);
        addContentPage(dataPage);
        addContentPage(settingsPage);
        addContentPage(tavernWebView);
        addContentPage(docsWebView);

        homeButton = createHomeButton();
        content.addView(homeButton, new FrameLayout.LayoutParams(
            dp(62),
            dp(34),
            Gravity.CENTER_VERTICAL | Gravity.END
        ));
        ((FrameLayout.LayoutParams) homeButton.getLayoutParams()).rightMargin = dp(8);
    }

    private View createHeader() {
        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(18), 0, dp(12), 0);
        header.setBackgroundColor(SIDEBAR);

        BrandMarkView mark = new BrandMarkView(this);
        header.addView(mark, new LinearLayout.LayoutParams(dp(36), dp(36)));

        LinearLayout brand = new LinearLayout(this);
        brand.setOrientation(LinearLayout.VERTICAL);
        brand.setPadding(dp(10), 0, 0, 0);
        TextView title = new TextView(this);
        title.setText("25小厨");
        title.setTextColor(INK);
        title.setTextSize(20);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        brand.addView(title);
        TextView subtitle = new TextView(this);
        subtitle.setText("CHEF25");
        subtitle.setTextColor(MUTED);
        subtitle.setTextSize(8);
        subtitle.setLetterSpacing(0.22f);
        brand.addView(subtitle);
        header.addView(brand, new LinearLayout.LayoutParams(
            0,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            1
        ));

        LinearLayout pageCopy = new LinearLayout(this);
        pageCopy.setOrientation(LinearLayout.VERTICAL);
        pageCopy.setGravity(Gravity.END);
        pageCopy.setPadding(dp(8), 0, dp(4), 0);
        pageTitle = new TextView(this);
        pageTitle.setText("我的酒馆");
        pageTitle.setTextColor(INK);
        pageTitle.setTextSize(14);
        pageTitle.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        pageTitle.setGravity(Gravity.END);
        pageCopy.addView(pageTitle);
        pageSubtitle = new TavernBrandView(this);
        pageCopy.addView(pageSubtitle, new LinearLayout.LayoutParams(dp(108), dp(18)));
        header.addView(pageCopy);

        InfoIconView about = new InfoIconView(this);
        about.setContentDescription("关于");
        about.setClickable(true);
        about.setOnClickListener(view -> showAbout());
        header.addView(about, new LinearLayout.LayoutParams(dp(36), dp(36)));
        return header;
    }

    private TextView createHomeButton() {
        TextView button = new TextView(this);
        button.setText("‹ 小厨");
        button.setTextColor(ACCENT);
        button.setTextSize(11);
        button.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        button.setGravity(Gravity.CENTER);
        button.setBackground(rounded(Color.argb(220, 23, 23, 23), 17));
        button.setContentDescription("返回小厨");
        button.setOnClickListener(view -> returnToLauncher());
        button.setVisibility(View.GONE);
        return button;
    }

    private void returnToLauncher() {
        tavernEntered = false;
        refreshNavigation();
        updateRuntimeState(RuntimeState.RUNNING);
    }

    private void applyShellLayout() {
        boolean inTavern = tavernEntered;
        if (root == null || header == null || tabBar == null || content == null) {
            return;
        }
        root.setPadding(0, inTavern ? 0 : safeTop, 0, inTavern ? 0 : safeBottom);
        root.setBackgroundColor(inTavern ? Color.rgb(23, 23, 23) : PAPER);
        content.setPadding(0, inTavern ? safeTop : 0, 0, inTavern ? safeBottom : 0);
        content.setBackgroundColor(inTavern ? Color.rgb(23, 23, 23) : Color.TRANSPARENT);
        header.setVisibility(inTavern ? View.GONE : View.VISIBLE);
        tabBar.setVisibility(inTavern ? View.GONE : View.VISIBLE);
        if (homeButton != null) {
            homeButton.setVisibility(inTavern ? View.VISIBLE : View.GONE);
        }
        configureSystemBars();
    }

    private LinearLayout createTabBar() {
        LinearLayout bar = new LinearLayout(this);
        bar.setOrientation(LinearLayout.HORIZONTAL);
        bar.setBackgroundColor(SIDEBAR);
        String[] labels = {"我的酒馆", "本地数据", "中文文档", "设置"};
        for (int index = 0; index < labels.length; index += 1) {
            LinearLayout tab = new LinearLayout(this);
            tab.setOrientation(LinearLayout.VERTICAL);
            tab.setGravity(Gravity.CENTER);
            tab.setPadding(0, dp(6), 0, dp(5));
            tab.setContentDescription(labels[index]);

            NavIconView icon = new NavIconView(this, index, MUTED);
            LinearLayout.LayoutParams iconParams = new LinearLayout.LayoutParams(dp(18), dp(18));
            iconParams.bottomMargin = dp(3);
            tab.addView(icon, iconParams);

            TextView label = new TextView(this);
            label.setText(labels[index]);
            label.setTextSize(10);
            label.setTextColor(MUTED);
            label.setGravity(Gravity.CENTER);
            tab.addView(label);
            final int tabIndex = index;
            tab.setOnClickListener(view -> showTab(tabIndex));
            tabViews[index] = label;
            tabIcons[index] = icon;
            LinearLayout.LayoutParams tabParams = new LinearLayout.LayoutParams(
                0,
                ViewGroup.LayoutParams.MATCH_PARENT,
                1
            );
            tabParams.setMargins(dp(4), dp(6), dp(4), dp(8));
            bar.addView(tab, tabParams);
        }
        return bar;
    }

    private void addContentPage(View page) {
        page.setVisibility(View.GONE);
        content.addView(page, new FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        ));
    }

    private ScrollView createLauncherPage() {
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        LinearLayout page = pageStack(scroll);
        page.setGravity(Gravity.CENTER_VERTICAL);

        LinearLayout hero = new LinearLayout(this);
        hero.setOrientation(LinearLayout.VERTICAL);
        hero.setGravity(Gravity.CENTER_HORIZONTAL);
        hero.setPadding(dp(20), dp(8), dp(20), dp(2));

        ChefMascotView mascot = new ChefMascotView(this);
        hero.addView(mascot, new LinearLayout.LayoutParams(dp(200), dp(150)));

        TextView heading = new TextView(this);
        heading.setText("故事，你来写。");
        heading.setTextColor(INK);
        heading.setTextSize(24);
        heading.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        heading.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams headingParams = new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        );
        headingParams.topMargin = dp(4);
        hero.addView(heading, headingParams);

        TextView subtitle = new TextView(this);
        subtitle.setText("开场，交给小厨。");
        subtitle.setTextColor(MUTED);
        subtitle.setTextSize(13);
        subtitle.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams subtitleParams = new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        );
        subtitleParams.topMargin = dp(4);
        hero.addView(subtitle, subtitleParams);
        page.addView(hero);

        primaryButton = new Button(this);
        primaryButton.setText("▶  一键启动酒馆");
        primaryButton.setTextColor(Color.WHITE);
        primaryButton.setTextSize(13);
        primaryButton.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        primaryButton.setAllCaps(false);
        primaryButton.setGravity(Gravity.CENTER);
        primaryButton.setMinWidth(dp(190));
        primaryButton.setBackground(rounded(PRIMARY, 8));
        primaryButton.setOnClickListener(view -> primaryAction());
        LinearLayout.LayoutParams primaryParams = new LinearLayout.LayoutParams(
            dp(210),
            dp(46)
        );
        primaryParams.gravity = Gravity.CENTER_HORIZONTAL;
        primaryParams.topMargin = dp(10);
        page.addView(primaryButton, primaryParams);

        LinearLayout statusRow = new LinearLayout(this);
        statusRow.setGravity(Gravity.CENTER);
        statusRow.setPadding(0, dp(10), 0, 0);
        statusDot = new TextView(this);
        statusDot.setText("●");
        statusDot.setTextColor(Color.rgb(176, 180, 165));
        statusDot.setTextSize(8);
        statusRow.addView(statusDot, new LinearLayout.LayoutParams(dp(14), dp(22)));
        statusTitle = new TextView(this);
        statusTitle.setText("酒馆尚未启动");
        statusTitle.setTextColor(MUTED);
        statusTitle.setTextSize(11);
        statusRow.addView(statusTitle, new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ));
        page.addView(statusRow);
        return scroll;
    }

    private ScrollView createDataPage() {
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        LinearLayout page = pageStack(scroll);

        LinearLayout storage = addCard(
            page,
            "存储目录",
            "",
            0
        );
        dataDirectory = new File(getFilesDir(), "chef25-data");
        TextView path = subtleText(dataDirectory.getAbsolutePath(), 11);
        path.setTypeface(Typeface.MONOSPACE);
        path.setTextIsSelectable(true);
        LinearLayout.LayoutParams pathParams = new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        );
        pathParams.topMargin = dp(8);
        storage.addView(path, pathParams);

        Button copy = secondaryButton("⧉  复制路径");
        copy.setOnClickListener(view -> copyDataPath());
        LinearLayout.LayoutParams copyParams = new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            dp(42)
        );
        copyParams.topMargin = dp(12);
        storage.addView(copy, copyParams);

        return scroll;
    }

    private ScrollView createSettingsPage() {
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        LinearLayout page = pageStack(scroll);

        LinearLayout launch = addCard(
            page,
            "启动端口",
            "",
            0
        );
        launch.addView(infoRow("当前地址", "127.0.0.1:8123"), rowParams(9));

        LinearLayout runtime = addCard(
            page,
            "内置运行时",
            "",
            12
        );
        runtime.addView(infoRow("Node.js", "v24.22.1"), rowParams(9));
        runtime.addView(infoRow("SillyTavern", "1.19.0"), rowParams(7));
        settingsStatus = new TextView(this);
        settingsStatus.setText("尚未启动");
        settingsStatus.setTextColor(MUTED);
        settingsStatus.setTextSize(12);
        settingsStatus.setGravity(Gravity.END);
        runtime.addView(infoRow("运行状态", settingsStatus), rowParams(7));

        return scroll;
    }

    private WebView createRuntimeWebView() {
        WebView webView = baseWebView(true);
        webView.setBackgroundColor(Color.BLACK);
        webView.setWebViewClient(new WebViewClient() {
            @Override
            public void onPageFinished(WebView view, String url) {
                Log.i(TAG, "SillyTavern page loaded");
                runAutomationIfRequested();
            }

            @Override
            public void onReceivedError(
                WebView view,
                WebResourceRequest request,
                WebResourceError error
            ) {
                if (request.isForMainFrame()) {
                    updateRuntimeState(new RuntimeState(
                        "FAILED",
                        "SillyTavern 页面加载失败：" + error.getDescription()
                    ));
                }
            }
        });
        return webView;
    }

    private WebView createDocsWebView() {
        WebView webView = baseWebView(true);
        webView.setWebViewClient(new WebViewClient());
        return webView;
    }

    private WebView baseWebView(boolean javascript) {
        WebView webView = new WebView(this);
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(javascript);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        return webView;
    }

    private LinearLayout pageStack(ScrollView scroll) {
        LinearLayout page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setPadding(dp(20), dp(18), dp(20), dp(24));
        scroll.addView(page, new ScrollView.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ));
        return page;
    }

    private LinearLayout card() {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(16), dp(16), dp(16), dp(16));
        GradientDrawable background = rounded(CARD, 10);
        background.setStroke(dp(1), LINE);
        card.setBackground(background);
        return card;
    }

    private LinearLayout addCard(
        LinearLayout page,
        String title,
        String body,
        int topMargin
    ) {
        LinearLayout card = card();
        TextView titleView = new TextView(this);
        titleView.setText(title);
        titleView.setTextColor(INK);
        titleView.setTextSize(14);
        titleView.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        card.addView(titleView);
        if (!body.isEmpty()) {
            TextView bodyView = subtleText(body, 12);
            LinearLayout.LayoutParams bodyParams = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            );
            bodyParams.topMargin = dp(7);
            card.addView(bodyView, bodyParams);
        }
        page.addView(card, cardParams(topMargin));
        return card;
    }

    private LinearLayout infoRow(String label, String value) {
        TextView valueView = new TextView(this);
        valueView.setText(value);
        valueView.setTextColor(MUTED);
        valueView.setTextSize(12);
        valueView.setGravity(Gravity.END);
        return infoRow(label, valueView);
    }

    private LinearLayout infoRow(String label, TextView value) {
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER_VERTICAL);
        TextView key = new TextView(this);
        key.setText(label);
        key.setTextColor(MUTED);
        key.setTextSize(12);
        row.addView(key, new LinearLayout.LayoutParams(
            0,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            1
        ));
        row.addView(value, new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ));
        return row;
    }

    private TextView subtleText(String text, int size) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextColor(MUTED);
        view.setTextSize(size);
        view.setLineSpacing(dp(2), 1);
        return view;
    }

    private Button secondaryButton(String label) {
        Button button = new Button(this);
        button.setText(label);
        button.setTextColor(INK);
        button.setTextSize(12);
        button.setAllCaps(false);
        button.setBackground(rounded(SIDEBAR, 8));
        return button;
    }

    private LinearLayout.LayoutParams cardParams(int topMargin) {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        );
        params.topMargin = dp(topMargin);
        return params;
    }

    private LinearLayout.LayoutParams buttonParams(int topMargin) {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            dp(50)
        );
        params.topMargin = dp(topMargin);
        return params;
    }

    private LinearLayout.LayoutParams rowParams(int topMargin) {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        );
        params.topMargin = dp(topMargin);
        return params;
    }

    private GradientDrawable rounded(int color, int radiusDp) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(color);
        drawable.setCornerRadius(dp(radiusDp));
        return drawable;
    }

    private void showTab(int index) {
        currentTab = index;
        if (index == 2 && !docsLoaded) {
            docsLoaded = true;
            docsWebView.loadUrl("https://www.chef25.com/guides/sillytavern/");
        }
        refreshNavigation();
    }

    private void refreshNavigation() {
        launcherPage.setVisibility(
            currentTab == 0 && !tavernEntered ? View.VISIBLE : View.GONE
        );
        dataPage.setVisibility(currentTab == 1 ? View.VISIBLE : View.GONE);
        docsWebView.setVisibility(currentTab == 2 ? View.VISIBLE : View.GONE);
        settingsPage.setVisibility(currentTab == 3 ? View.VISIBLE : View.GONE);
        tavernWebView.setVisibility(
            currentTab == 0 && tavernEntered ? View.VISIBLE : View.GONE
        );

        boolean inTavern = currentTab == 0 && tavernEntered;
        String[] titles = {"我的酒馆", "本地数据", "中文文档", "设置"};
        pageTitle.setText(titles[currentTab]);
        pageSubtitle.setVisibility(currentTab == 0 ? View.VISIBLE : View.GONE);
        for (int tabIndex = 0; tabIndex < tabViews.length; tabIndex += 1) {
            TextView tab = tabViews[tabIndex];
            boolean selected = tabIndex == currentTab;
            tab.setTextColor(selected ? SELECTED : MUTED);
            tabIcons[tabIndex].setIconColor(selected ? SELECTED : MUTED);
            ViewGroup parent = (ViewGroup) tab.getParent();
            parent.setBackground(
                selected ? rounded(ACCENT_SOFT, 8) :
                rounded(Color.TRANSPARENT, 8)
            );
        }
        applyShellLayout();
    }

    private void primaryAction() {
        if (runtimeReady) {
            enterTavern();
        } else {
            startRuntime();
        }
    }

    private void startRuntime() {
        if (runtimeStarted) {
            return;
        }
        runtimeStarted = true;
        updateRuntimeState(RuntimeState.STARTING);
        startupExecutor.execute(this::prepareAndStartRuntime);
    }

    private void prepareAndStartRuntime() {
        try {
            projectDirectory = new File(getFilesDir(), "sillytavern");
            dataDirectory = new File(getFilesDir(), "chef25-data");
            ensureDirectory(dataDirectory);
            ensureRuntimeExtracted(projectDirectory);

            File server = new File(projectDirectory, "server.js");
            File bootstrap = new File(
                projectDirectory,
                ".chef25-runtime/WebAssemblyTiktokenBootstrap.cjs"
            );
            File config = new File(dataDirectory, "config.yaml");
            if (!server.isFile() || !bootstrap.isFile()) {
                throw new IOException("Packaged SillyTavern runtime is incomplete");
            }

            String[] arguments = {
                "node",
                "--require",
                bootstrap.getAbsolutePath(),
                server.getAbsolutePath(),
                "--port=8123",
                "--enableIPv4=true",
                "--enableIPv6=false",
                "--listen=false",
                "--browserLaunchEnabled=false",
                "--whitelist=false",
                "--configPath=" + config.getAbsolutePath(),
                "--dataRoot=" + dataDirectory.getAbsolutePath(),
            };

            Thread nodeThread = new Thread(() -> {
                try {
                    int result = startNodeWithArguments(arguments, getFilesDir().getAbsolutePath());
                    Log.i(TAG, "Node runtime exited with code " + result);
                } catch (Throwable error) {
                    Log.e(TAG, "Node runtime failed", error);
                    mainHandler.post(() -> updateRuntimeState(new RuntimeState(
                        "FAILED",
                        "Node.js 启动失败：" + error.getMessage()
                    )));
                }
            }, "Chef25 Node.js");
            nodeThread.setDaemon(false);
            nodeThread.start();

            mainHandler.post(this::pollReadiness);
        } catch (Throwable error) {
            Log.e(TAG, "Runtime preparation failed", error);
            mainHandler.post(() -> updateRuntimeState(new RuntimeState(
                "FAILED",
                "启动失败：" + error.getMessage()
            )));
        }
    }

    private void ensureRuntimeExtracted(File destination) throws IOException {
        File marker = new File(destination, RUNTIME_MARKER);
        if (
            new File(destination, "server.js").isFile()
                && marker.isFile()
                && RUNTIME_VERSION.equals(readSmallText(marker).trim())
        ) {
            Log.i(TAG, "Using existing extracted runtime");
            return;
        }

        Log.i(TAG, "Extracting packaged SillyTavern runtime");
        deleteRecursively(destination);
        ensureDirectory(destination);

        try (
            InputStream raw = getAssets().open(RUNTIME_ZIP);
            ZipInputStream zip = new ZipInputStream(new BufferedInputStream(raw))
        ) {
            ZipEntry entry;
            byte[] buffer = new byte[65536];
            while ((entry = zip.getNextEntry()) != null) {
                File target = safeResolvedChild(destination, entry.getName());
                if (entry.isDirectory()) {
                    ensureDirectory(target);
                } else {
                    File parent = target.getParentFile();
                    if (parent != null) {
                        ensureDirectory(parent);
                    }
                    try (FileOutputStream output = new FileOutputStream(target)) {
                        int count;
                        while ((count = zip.read(buffer)) != -1) {
                            output.write(buffer, 0, count);
                        }
                    }
                }
                zip.closeEntry();
            }
        }

        try (FileOutputStream output = new FileOutputStream(marker)) {
            output.write(RUNTIME_VERSION.getBytes(StandardCharsets.UTF_8));
        }
    }

    private void pollReadiness() {
        if (readinessAttempts++ >= 240) {
            updateRuntimeState(new RuntimeState(
                "FAILED",
                "等待 SillyTavern 监听超时，请查看 logcat。"
            ));
            return;
        }

        startupExecutor.execute(() -> {
            boolean ready = false;
            try {
                HttpURLConnection connection = (HttpURLConnection) new URL(
                    "http://127.0.0.1:8123/version"
                ).openConnection();
                connection.setConnectTimeout(1000);
                connection.setReadTimeout(1000);
                int statusCode = connection.getResponseCode();
                if (statusCode == 200) {
                    try (InputStream input = connection.getInputStream()) {
                        String body = new String(input.readAllBytes(), StandardCharsets.UTF_8);
                        ready = body.contains("1.19.0");
                    }
                }
                connection.disconnect();
            } catch (IOException ignored) {
                // The Node process is still starting or compiling the frontend.
            }

            boolean runtimeReady = ready;
            mainHandler.post(() -> {
                if (runtimeReady) {
                    updateRuntimeState(RuntimeState.RUNNING);
                    if (getIntent().getStringExtra("CHEF25_UI_TEST_MESSAGE") != null) {
                        enterTavern();
                    }
                } else {
                    mainHandler.postDelayed(this::pollReadiness, 500);
                }
            });
        });
    }

    private void enterTavern() {
        if (!runtimeReady) {
            return;
        }
        tavernEntered = true;
        if (!tavernLoaded) {
            tavernLoaded = true;
            tavernWebView.loadUrl("http://127.0.0.1:8123/");
        }
        updateRuntimeState(RuntimeState.RUNNING);
        refreshNavigation();
    }

    private void updateRuntimeState(RuntimeState state) {
        switch (state.kind) {
            case "STOPPED":
                statusDot.setTextColor(Color.rgb(176, 180, 165));
                statusTitle.setText("酒馆尚未启动");
                primaryButton.setText("▶  一键启动酒馆");
                primaryButton.setEnabled(true);
                setSettingsStatus("尚未启动");
                break;
            case "STARTING":
                statusDot.setTextColor(AMBER);
                statusTitle.setText("小厨正在准备…");
                primaryButton.setText("正在准备…");
                primaryButton.setEnabled(false);
                setSettingsStatus("启动中");
                break;
            case "RUNNING":
                runtimeReady = true;
                statusDot.setTextColor(GREEN);
                statusTitle.setText("酒馆运行中");
                primaryButton.setText(tavernEntered ? "正在酒馆中" : "进入酒馆  →");
                primaryButton.setEnabled(!tavernEntered);
                setSettingsStatus("运行中");
                break;
            case "FAILED":
                runtimeReady = false;
                statusDot.setTextColor(ERROR);
                statusTitle.setText("启动失败");
                primaryButton.setText("启动失败，请重启 App");
                primaryButton.setEnabled(false);
                setSettingsStatus("启动失败");
                break;
            default:
                break;
        }
    }

    private void setSettingsStatus(String text) {
        if (settingsStatus != null) {
            settingsStatus.setText(text);
        }
    }

    private void copyDataPath() {
        ClipboardManager clipboard =
            (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        clipboard.setPrimaryClip(ClipData.newPlainText("25小厨存储路径", dataDirectory.getAbsolutePath()));
        new AlertDialog.Builder(this)
            .setTitle("已复制")
            .setMessage("存储路径已复制到剪贴板。")
            .setPositiveButton("好", null)
            .show();
    }

    private void showAbout() {
        new AlertDialog.Builder(this)
            .setTitle("25小厨 Mobile")
            .setMessage(
                "SillyTavern 1.19.0\n"
                    + "Node.js v24.22.1"
            )
            .setPositiveButton("关闭", null)
            .show();
    }

    private void runAutomationIfRequested() {
        String message = getIntent().getStringExtra("CHEF25_UI_TEST_MESSAGE");
        if (message == null || message.isEmpty() || automationStarted) {
            return;
        }
        automationStarted = true;

        String apiURL = getIntent().getStringExtra("CHEF25_UI_TEST_API_URL");
        String model = getIntent().getStringExtra("CHEF25_UI_TEST_MODEL");
        JSONArray values = new JSONArray()
            .put(message)
            .put(apiURL == null ? "" : apiURL)
            .put(model == null ? "" : model);

        String script =
            "(async () => {"
                + "const [text, apiURL, model] = " + values + ";"
                + "const log = value => console.log('[Chef25 automation] ' + value);"
                + "const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));"
                + "const waitFor = async (predicate, timeout, label) => {"
                + "const started = Date.now();"
                + "while (!predicate()) {"
                + "if (Date.now() - started > timeout) throw new Error('Timed out: ' + label);"
                + "await sleep(250);"
                + "}"
                + "};"
                + "let onboardingDismissed = false;"
                + "const onboardingTimer = setInterval(() => {"
                + "const popup = Array.from(document.querySelectorAll('.popup'))"
                + ".find(element => element.querySelector('.onboarding'));"
                + "if (!popup) return;"
                + "const button = popup.querySelector('.popup-button-ok');"
                + "if (button) {"
                + "button.click();"
                + "onboardingDismissed = true;"
                + "clearInterval(onboardingTimer);"
                + "log('onboarding dismissed');"
                + "}"
                + "}, 250);"
                + "await waitFor(() => window.jQuery && "
                + "document.querySelector('#main_api') && "
                + "document.querySelector('#send_textarea'), 40000, 'UI controls');"
                + "clearInterval(onboardingTimer);"
                + "if (apiURL) {"
                + "const jq = window.jQuery;"
                + "jq('#main_api').val('openai').trigger('change');"
                + "await sleep(500);"
                + "jq('#chat_completion_source').val('custom').trigger('change');"
                + "await sleep(500);"
                + "jq('#custom_api_url_text').val(apiURL).trigger('input');"
                + "jq('#custom_model_id')"
                + ".val(model || 'chef25-local-fake').trigger('input');"
                + "jq('#api_key_custom').val('').trigger('input');"
                + "await sleep(1000);"
                + "const openai = await import(document.location.origin + '/scripts/openai.js');"
                + "const st = await import(document.location.origin + '/script.js');"
                + "if (st.main_api !== 'openai') "
                + "throw new Error('Main API did not switch to openai');"
                + "if (openai.oai_settings.chat_completion_source !== 'custom') "
                + "throw new Error('Chat completion source did not switch to custom');"
                + "if (openai.oai_settings.custom_url !== apiURL) "
                + "throw new Error('Custom API URL was not applied');"
                + "log('custom API configured: ' + apiURL + ' / ' + model);"
                + "}"
                + "await waitFor(() => "
                + "document.querySelector('#send_textarea') && "
                + "document.querySelector('#send_but'), 10000, 'send controls');"
                + "const textarea = document.querySelector('#send_textarea');"
                + "textarea.focus();"
                + "textarea.value = text;"
                + "textarea.dispatchEvent(new InputEvent('input', {"
                + "bubbles: true, inputType: 'insertText', data: text"
                + "}));"
                + "await sleep(500);"
                + "const sendButton = document.querySelector('#send_but');"
                + "sendButton.click();"
                + "log('message submitted: ' + text);"
                + "})().catch(error => console.error('[Chef25 automation]', error));";

        tavernWebView.evaluateJavascript(script, null);
    }

    private void ensureDirectory(File directory) throws IOException {
        if (!directory.isDirectory() && !directory.mkdirs()) {
            throw new IOException("Could not create directory: " + directory);
        }
    }

    private File safeResolvedChild(File root, String entryName) throws IOException {
        File target = new File(root, entryName).getCanonicalFile();
        if (!target.toPath().startsWith(root.getCanonicalFile().toPath())) {
            throw new IOException("Unsafe archive entry: " + entryName);
        }
        return target;
    }

    private String readSmallText(File file) throws IOException {
        byte[] bytes = new byte[1024];
        try (InputStream input = new java.io.FileInputStream(file)) {
            int count = input.read(bytes);
            return count <= 0 ? "" : new String(bytes, 0, count, StandardCharsets.UTF_8);
        }
    }

    private void deleteRecursively(File file) throws IOException {
        if (!file.exists()) {
            return;
        }
        File[] children = file.listFiles();
        if (children != null) {
            for (File child : children) {
                deleteRecursively(child);
            }
        }
        if (!file.delete()) {
            throw new IOException("Could not delete: " + file);
        }
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private float dpf(float value) {
        return value * getResources().getDisplayMetrics().density;
    }

    private float sp(float value) {
        return value * getResources().getDisplayMetrics().scaledDensity;
    }

    private final class NavIconView extends View {
        private final int kind;
        private int iconColor;
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);

        NavIconView(Context context, int kind, int iconColor) {
            super(context);
            this.kind = kind;
            this.iconColor = iconColor;
            setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);
        }

        void setIconColor(int color) {
            iconColor = color;
            invalidate();
        }

        @Override
        protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            float scale = Math.min(getWidth(), getHeight()) / 18f;
            canvas.save();
            canvas.scale(scale, scale);
            paint.setColor(iconColor);
            paint.setStyle(Paint.Style.STROKE);
            paint.setStrokeWidth(1.8f);
            paint.setStrokeCap(Paint.Cap.ROUND);
            paint.setStrokeJoin(Paint.Join.ROUND);

            if (kind == 0) {
                canvas.drawRoundRect(new RectF(3, 7, 12.5f, 15), 2, 2, paint);
                Path handle = new Path();
                handle.moveTo(12.5f, 8.5f);
                handle.cubicTo(17.5f, 8.5f, 17.5f, 14, 12.5f, 14);
                canvas.drawPath(handle, paint);
                Path steam = new Path();
                steam.moveTo(6.5f, 5.5f);
                steam.quadTo(5f, 4, 6.5f, 2.5f);
                steam.moveTo(10f, 5.5f);
                steam.quadTo(8.5f, 4, 10f, 2.5f);
                canvas.drawPath(steam, paint);
            } else if (kind == 1) {
                Path folder = new Path();
                folder.moveTo(2.5f, 5);
                folder.quadTo(2.5f, 3, 4.5f, 3);
                folder.lineTo(7, 3);
                folder.lineTo(9, 5);
                folder.lineTo(14, 5);
                folder.quadTo(15.5f, 5, 15.5f, 6.5f);
                folder.lineTo(15.5f, 14);
                folder.quadTo(15.5f, 15.5f, 14, 15.5f);
                folder.lineTo(4, 15.5f);
                folder.quadTo(2.5f, 15.5f, 2.5f, 14);
                folder.close();
                canvas.drawPath(folder, paint);
            } else if (kind == 2) {
                canvas.drawCircle(9, 9, 7, paint);
                paint.setStyle(Paint.Style.FILL);
                paint.setTypeface(Typeface.DEFAULT_BOLD);
                paint.setTextAlign(Paint.Align.CENTER);
                paint.setTextSize(10.5f);
                canvas.drawText("?", 9, 12.7f, paint);
            } else {
                Path gear = new Path();
                float[] radii = {7.3f, 5.7f};
                for (int point = 0; point < 16; point += 1) {
                    double angle = Math.PI * point / 8 - Math.PI / 2;
                    float radius = radii[point % 2];
                    float x = 9 + (float) Math.cos(angle) * radius;
                    float y = 9 + (float) Math.sin(angle) * radius;
                    if (point == 0) {
                        gear.moveTo(x, y);
                    } else {
                        gear.lineTo(x, y);
                    }
                }
                gear.close();
                canvas.drawPath(gear, paint);
                canvas.drawCircle(9, 9, 2.3f, paint);
            }
            canvas.restore();
        }
    }

    private final class InfoIconView extends View {
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);

        InfoIconView(Context context) {
            super(context);
        }

        @Override
        protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            float targetSize = Math.min(getWidth(), getHeight()) * 20f / 36f;
            float scale = targetSize / 24f;
            float offsetX = (getWidth() - targetSize) / 2f;
            float offsetY = (getHeight() - targetSize) / 2f;
            canvas.save();
            canvas.translate(offsetX, offsetY);
            canvas.scale(scale, scale);
            paint.setColor(MUTED);
            paint.setStyle(Paint.Style.STROKE);
            paint.setStrokeWidth(1.8f);
            paint.setStrokeCap(Paint.Cap.ROUND);
            canvas.drawCircle(12, 12, 9, paint);
            paint.setStyle(Paint.Style.FILL);
            canvas.drawCircle(12, 7.5f, 1, paint);
            Path stem = new Path();
            stem.moveTo(12, 11);
            stem.lineTo(12, 16.5f);
            paint.setStyle(Paint.Style.STROKE);
            canvas.drawPath(stem, paint);
            canvas.restore();
        }
    }

    private final class TavernBrandView extends View {
        private final Paint captionPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint namePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint underlinePaint = new Paint(Paint.ANTI_ALIAS_FLAG);

        TavernBrandView(Context context) {
            super(context);
            captionPaint.setColor(Color.rgb(132, 131, 120));
            captionPaint.setTextSize(sp(9));
            captionPaint.setTypeface(Typeface.DEFAULT);
            namePaint.setColor(ACCENT);
            namePaint.setTextSize(sp(10.5f));
            namePaint.setTypeface(Typeface.DEFAULT_BOLD);
            underlinePaint.setColor(Color.rgb(245, 173, 146));
            underlinePaint.setStyle(Paint.Style.STROKE);
            underlinePaint.setStrokeWidth(dp(1));
            underlinePaint.setStrokeCap(Paint.Cap.ROUND);
            setContentDescription("基于 SillyTavern");
        }

        @Override
        protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            Paint.FontMetrics captionMetrics = captionPaint.getFontMetrics();
            Paint.FontMetrics nameMetrics = namePaint.getFontMetrics();
            float baseline = (getHeight() - nameMetrics.ascent - nameMetrics.descent) / 2f;
            float captionWidth = captionPaint.measureText("基于");
            float nameWidth = namePaint.measureText("SillyTavern");
            float gap = dp(5);
            float totalWidth = captionWidth + gap + nameWidth;
            float x = getWidth() - totalWidth;
            canvas.drawText(
                "基于",
                x,
                baseline + (captionMetrics.descent - nameMetrics.descent) / 2f,
                captionPaint
            );
            float nameX = x + captionWidth + gap;
            canvas.drawText("SillyTavern", nameX, baseline, namePaint);

            Path underline = new Path();
            underline.moveTo(nameX - dp(1), dpf(13.5f));
            underline.cubicTo(
                nameX + nameWidth * 0.35f, dpf(12),
                nameX + nameWidth * 0.7f, dpf(12.5f),
                nameX + nameWidth + dp(1), dp(13)
            );
            underline.moveTo(nameX + dp(2), dp(16));
            underline.cubicTo(
                nameX + nameWidth * 0.35f, dpf(14),
                nameX + nameWidth * 0.72f, dpf(14.5f),
                nameX + nameWidth - dp(2), dpf(15.5f)
            );
            canvas.drawPath(underline, underlinePaint);
        }
    }

    private final class BrandMarkView extends View {
        BrandMarkView(Context context) {
            super(context);
            setContentDescription("25小厨 Logo");
        }

        @Override
        protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            float width = getWidth();
            float height = getHeight();

            Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG);
            fill.setColor(ACCENT);
            canvas.save();
            canvas.rotate(-5, width / 2f, height / 2f);
            canvas.drawRoundRect(
                new RectF(0, 0, width, height),
                width * 12f / 38f,
                height * 12f / 38f,
                fill
            );

            float iconSize = width * 25f / 38f;
            float scale = iconSize / 24f;
            float offsetX = (width - iconSize) / 2f;
            float offsetY = (height - iconSize) / 2f;
            Paint stroke = new Paint(Paint.ANTI_ALIAS_FLAG);
            stroke.setColor(Color.rgb(255, 249, 238));
            stroke.setStyle(Paint.Style.STROKE);
            stroke.setStrokeWidth(1.8f * scale);
            stroke.setStrokeCap(Paint.Cap.ROUND);
            stroke.setStrokeJoin(Paint.Join.ROUND);

            Path hat = new Path();
            hat.moveTo(offsetX + 17 * scale, offsetY + 21 * scale);
            hat.cubicTo(
                offsetX + 16.45f * scale, offsetY + 21 * scale,
                offsetX + 17 * scale, offsetY + 20.55f * scale,
                offsetX + 17 * scale, offsetY + 20 * scale
            );
            hat.lineTo(offsetX + 17 * scale, offsetY + 14.65f * scale);
            hat.cubicTo(
                offsetX + 17 * scale, offsetY + 14.193f * scale,
                offsetX + 17.316f * scale, offsetY + 13.806f * scale,
                offsetX + 17.727f * scale, offsetY + 13.609f * scale
            );
            hat.cubicTo(
                offsetX + 21.727f * scale, offsetY + 11.731f * scale,
                offsetX + 21.245f * scale, offsetY + 5.9f * scale,
                offsetX + 17.083f * scale, offsetY + 6.05f * scale
            );
            hat.cubicTo(
                offsetX + 15.186f * scale, offsetY + 3.156f * scale,
                offsetX + 8.814f * scale, offsetY + 3.156f * scale,
                offsetX + 6.917f * scale, offsetY + 6.05f * scale
            );
            hat.cubicTo(
                offsetX + 2.755f * scale, offsetY + 5.9f * scale,
                offsetX + 2.273f * scale, offsetY + 11.731f * scale,
                offsetX + 6.273f * scale, offsetY + 13.609f * scale
            );
            hat.cubicTo(
                offsetX + 6.684f * scale, offsetY + 13.806f * scale,
                offsetX + 7 * scale, offsetY + 14.193f * scale,
                offsetX + 7 * scale, offsetY + 14.65f * scale
            );
            hat.lineTo(offsetX + 7 * scale, offsetY + 20 * scale);
            hat.cubicTo(
                offsetX + 7 * scale, offsetY + 20.552f * scale,
                offsetX + 7.448f * scale, offsetY + 21 * scale,
                offsetX + 8 * scale, offsetY + 21 * scale
            );
            hat.close();
            canvas.drawPath(hat, stroke);

            Path band = new Path();
            band.moveTo(offsetX + 6 * scale, offsetY + 17 * scale);
            band.lineTo(offsetX + 18 * scale, offsetY + 17 * scale);
            canvas.drawPath(band, stroke);
            canvas.restore();
        }
    }

    private final class ChefMascotView extends View {
        ChefMascotView(Context context) {
            super(context);
            setContentDescription("小厨，陪你开启故事的厨师帽吉祥物");
        }

        @Override
        protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            float scale = Math.min(getWidth() / 200f, getHeight() / 150f);
            float originX = (getWidth() - 200f * scale) / 2f;
            float originY = (getHeight() - 150f * scale) / 2f;

            Paint halo = new Paint(Paint.ANTI_ALIAS_FLAG);
            halo.setShader(new RadialGradient(
                0,
                0,
                100f * scale,
                new int[] {
                    Color.rgb(245, 236, 218),
                    Color.rgb(245, 236, 218),
                    Color.argb(0, 245, 236, 218),
                },
                new float[] {0f, 0.05f, 0.68f},
                Shader.TileMode.CLAMP
            ));
            canvas.save();
            canvas.translate(originX + 100f * scale, originY + 75f * scale);
            canvas.scale(1f, 0.75f);
            canvas.drawCircle(0, 0, 100f * scale, halo);
            canvas.restore();

            Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG);
            fill.setStyle(Paint.Style.FILL);
            fill.setColor(Color.argb(166, 233, 220, 195));
            canvas.save();
            canvas.translate(originX, originY);
            canvas.scale(scale, scale);
            canvas.drawOval(new RectF(56, 129, 144, 139), fill);

            fill.setColor(Color.rgb(214, 180, 111));
            Path sparkle = new Path();
            sparkle.moveTo(27, 36);
            sparkle.quadTo(27, 58, 17, 58);
            sparkle.quadTo(27, 58, 27, 80);
            sparkle.quadTo(27, 58, 37, 58);
            sparkle.quadTo(27, 58, 27, 36);
            sparkle.close();
            canvas.drawPath(sparkle, fill);

            Paint stroke = new Paint(Paint.ANTI_ALIAS_FLAG);
            stroke.setStyle(Paint.Style.STROKE);
            stroke.setColor(Color.rgb(214, 180, 111));
            stroke.setStrokeWidth(1.3f);
            Path smallSparkle = new Path();
            smallSparkle.moveTo(170, 99);
            smallSparkle.lineTo(173, 105);
            smallSparkle.lineTo(179, 108);
            smallSparkle.lineTo(173, 111);
            smallSparkle.lineTo(170, 117);
            smallSparkle.lineTo(167, 111);
            smallSparkle.lineTo(161, 108);
            smallSparkle.lineTo(167, 105);
            smallSparkle.close();
            canvas.drawPath(smallSparkle, stroke);

            fill.setStyle(Paint.Style.FILL);
            fill.setColor(Color.rgb(255, 240, 214));
            Path hat = new Path();
            hat.moveTo(67, 87);
            hat.cubicTo(43, 79, 45, 47, 70, 46);
            hat.cubicTo(81, 19, 112, 19, 124, 46);
            hat.cubicTo(151, 44, 158, 77, 134, 88);
            hat.lineTo(134, 117);
            hat.quadTo(134, 122, 129, 122);
            hat.lineTo(72, 122);
            hat.quadTo(67, 122, 67, 117);
            hat.close();
            canvas.drawPath(hat, fill);
            stroke.setColor(Color.rgb(204, 139, 80));
            stroke.setStrokeWidth(5);
            stroke.setStrokeJoin(Paint.Join.ROUND);
            canvas.drawPath(hat, stroke);
            Path band = new Path();
            band.moveTo(69, 105);
            band.lineTo(132, 105);
            stroke.setStrokeWidth(4);
            stroke.setStrokeCap(Paint.Cap.ROUND);
            canvas.drawPath(band, stroke);

            fill.setColor(Color.argb(38, 234, 164, 135));
            canvas.drawOval(new RectF(70, 89, 82, 95), fill);
            canvas.drawOval(new RectF(118, 89, 130, 95), fill);

            stroke.setColor(Color.rgb(145, 107, 73));
            stroke.setStrokeWidth(4.5f);
            Path eyes = new Path();
            eyes.moveTo(85, 81);
            eyes.quadTo(85, 86, 85, 81);
            eyes.moveTo(115, 81);
            eyes.quadTo(115, 86, 115, 81);
            canvas.drawPath(eyes, stroke);
            Path mouth = new Path();
            mouth.moveTo(96, 91);
            mouth.quadTo(100, 98, 104, 91);
            stroke.setStrokeWidth(2.5f);
            canvas.drawPath(mouth, stroke);
            canvas.restore();
        }
    }

    private static final class RuntimeState {
        static final RuntimeState STOPPED = new RuntimeState("STOPPED", "");
        static final RuntimeState STARTING = new RuntimeState("STARTING", "");
        static final RuntimeState RUNNING = new RuntimeState("RUNNING", "");

        final String kind;
        final String message;

        RuntimeState(String kind, String message) {
            this.kind = kind;
            this.message = message;
        }
    }
}
