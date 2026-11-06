# Android Node runtime spike

This app runs the upstream SillyTavern 1.19.0 `server.js` in an Android app. The
release pipeline locks Node.js 24.22.1, extracts the packaged SillyTavern source
and dependencies into app-private storage, and exposes a Desktop-inspired
Chef25 launcher. The primary action starts Node on a native thread; the Tavern
tab then loads `http://127.0.0.1:8123` in a persistent `WebView`.

The mobile shell includes the home/start flow, runtime status, Tavern, local
data path with copy action, Chinese usage guide, settings/about information,
and a push-aside drawer opened from the top-left menu or a left-edge pan.
The drawer tracks horizontal dragging, has a scrollable menu and a fixed About
entry at the bottom. The home shows startup status only on its primary button and opens the Tavern
automatically once ready, provided the user has stayed on the home page. The light
“返回小厨” bubble can be dragged and snaps to the nearer side in about 491 ms;
a drag never triggers its return action. Reduced-motion settings disable the snap
animation. The home mascot loops automatically while the home is
visible and the app is active; system reduced-motion settings are respected.

Settings includes a destructive local-data reset with an exact `确认重置` confirmation.
If Node has started in this process, reset is deferred until a full app termination
and relaunch; backgrounding is insufficient. Pending/failed resets block startup
and retry on launch. See the [root README](../../README.md) for deletion scope
and platform-specific termination steps. Port editing, ZIP transfer and updates
remain unimplemented.

Current emulator results, evidence hashes, build findings, and limits are in
[`docs/android-node-runtime.md`](../../docs/android-node-runtime.md).

The runtime requires:

- `rsvg-convert` from librsvg to generate the checked-in app icon assets;
- an arm64 Node.js 24.22.1 `libnode.so` from the pinned nodejs-mobile release;
- small ICU (`--with-intl=small-icu --with-icu-locales=root,en`) because
SillyTavern uses Unicode property regular expressions;
- a prepared SillyTavern checkout containing `node_modules`;
- Gradle 9.3.1 and the Android SDK/NDK used by `app/build.gradle`.

Fetch the pinned runtime and build a debug APK:

```sh
node ../../scripts/fetch-node-mobile.mjs android
node ../../scripts/prepare-sillytavern.mjs android
ST_SOURCE=../../.build/sillytavern-android \
./build-apk.sh debug
```

The release workflow uses `build-apk.sh release` with a protected Android
keystore. Node stdout and stderr are written to the app-private
`files/node-output.log`.

Install while preserving app data and run the UI test:

```sh
adb -s emulator-5554 install -r \
  app/build/outputs/apk/debug/app-debug.apk
adb -s emulator-5554 shell am start \
  -n com.chef25.mobile.nodespike/.MainActivity \
  --es CHEF25_UI_TEST_MESSAGE 'Android-Auto-API-SSE-20261104' \
  --es CHEF25_UI_TEST_API_URL 'http://10.0.2.2:8124/v1' \
  --es CHEF25_UI_TEST_MODEL 'chef25-local-fake'
```

The automation waits for SillyTavern `APP_READY`, selects the Custom Chat
Completion API, verifies the URL and source, then injects one message through
the page UI. Supplying `CHEF25_UI_TEST_MESSAGE` auto-starts the runtime for that
test only. This harness is debug-only and has no foreground service or long-term
background guarantee.
