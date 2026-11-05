# iOS Node runtime spike

This app runs the upstream SillyTavern 1.19.0 `server.js` inside an iOS app
through `NodeMobile.xcframework`. The release pipeline locks Node.js 24.22.1.
The app first opens a Chef25 launcher shell; its primary action starts Node.js
on a background thread, waits
for `http://127.0.0.1:8123/version`, and then opens the original UI in
`WKWebView`.

The shell provides a Desktop-inspired home, runtime status, the Tavern entry,
the app-private data directory, the Chinese usage guide, settings/about
information, and persistent bottom navigation. It intentionally omits Desktop
port editing, reset, ZIP transfer and updates until those operations have
mobile-specific safety and UX.

The committed source is a test harness, not a production client. Current
simulator and iPhone results, evidence hashes, and known limits are recorded in
[`docs/ios-node-runtime.md`](../../docs/ios-node-runtime.md).

Requirements:

- Xcode with the requested iPhoneOS or Simulator SDK
- `rsvg-convert` from librsvg to generate the checked-in app icon assets
- a prepared SillyTavern checkout containing `node_modules`
- the pinned Node.js 24 `NodeMobile.xcframework`
- a development signing identity and provisioning profile for a device build

The Action generates a native Xcode project with XcodeGen and archives it for
TestFlight. For a local simulator build:

```sh
node ../../scripts/fetch-node-mobile.mjs ios
node ../../scripts/prepare-sillytavern.mjs ios
xcodegen generate
xcodebuild -project Chef25Mobile.xcodeproj -scheme Chef25 \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

The previous manual device helper remains available for diagnostics, but the
public build path uses `project.yml`. Build and sign for an iPhone:

```sh
ST_SOURCE=/path/to/SillyTavern \
NODE_MOBILE_FRAMEWORK=/path/to/NodeMobile.framework \
IOS_TARGET=device \
OUT_DIR=/path/to/output \
SIGNING_IDENTITY="$IOS_SIGNING_IDENTITY" \
PROVISIONING_PROFILE=/path/to/profile.mobileprovision \
./build-simulator.sh
```

Install and launch:

```sh
xcrun devicectl device install app --device "$IOS_CORE_DEVICE_ID" \
  /path/to/output/Chef25NodeSpike.app
xcrun devicectl device process launch --device "$IOS_CORE_DEVICE_ID" \
  --terminate-existing --console com.chef25.mobile.node-spike
```

When `CHEF25_UI_TEST_MESSAGE` is present, the harness auto-starts so existing
automation can enter the Tavern without a tap. The three test environment
variables read by the host are
`CHEF25_UI_TEST_MESSAGE`, `CHEF25_UI_TEST_API_URL`, and
`CHEF25_UI_TEST_MODEL`.
