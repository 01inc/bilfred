# Bilfred iOS

Native SwiftUI, iOS 26 or later. Generate the Xcode project with XcodeGen 2.46:

```sh
xcodegen generate --spec apps/ios/project.yml
```

Use a locally configured Apple team for signed simulator and archive builds.
Keep that account mapping in ignored `.local/` or `Signing.xcconfig`; never commit
certificates, profiles or private keys. Do not disable signing for the simulator:
the installation credential must persist in Keychain across relaunches.

The default API origin is `http://localhost:8008`. Override `BILFRED_API_BASE_URL`
with your own HTTPS origin for a device build. Provider keys never enter the app.
The generated `.xcodeproj` is ignored; `project.yml` is the source of truth and
pins ConfettiSwiftUI to 3.0.0. Run XcodeGen again after adding local resources.

The supplied demo photo is excluded from Git. Optionally place a licensed photo
at `Bilfred/Resources/superb.png`; without it, the app uses a system illustration.
The car/home/receipt cache uses protected local storage.

The visual system uses neutral semantic colors, native system
text, adaptive surfaces and blue accent. The car cover uses native image clipping,
gradient and material. Main navigation is the native **Bil** / **Historikk** TabView.

Journey: plate → vehicle/mileage → maintenance → three options → desired date/time
→ offer and Apple Pay/Vipps example selection → swipe → saved demo history.
History supports simulated rescheduling and completion. No payment sheet or real
workshop booking is opened.

`BilfredUITests` runs the deterministic local demo in an isolated cache namespace.
It checks option selection, the date step, payment choice, partial/full swipe,
history, rescheduling, completion and relaunch. Live API checks are separate.
Build logs, screenshots, test results, archives and export receipts belong in
ignored `.local/verification/` and `.local/distribution/`.

Example simulator build (substitute your local team and available simulator):

```sh
xcodebuild -project apps/ios/Bilfred.xcodeproj -scheme Bilfred \
  -destination 'platform=iOS Simulator,name=iPhone 17e' \
  DEVELOPMENT_TEAM=YOUR_TEAM CODE_SIGN_IDENTITY=- build
```

Use the same command with `test` to run the UI suite. The `--ui-testing` launch
argument isolates persistence and uses local synthetic responses. Reduce Motion
suppresses confetti. Keyboard inputs include an explicit close control.

The app icon uses the landing page and keynote black–indigo–gray gradient.
UI tests enter `DEMO` with `--ui-testing`; this fixture path is compiled only in
Debug. There is no demo-car button in the customer interface.
