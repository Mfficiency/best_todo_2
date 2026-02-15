# BestToDo

📝 Swipe-first, ultra-fast to-do app built with Flutter. Tasks default to today. Move with gestures. Notes, labels, and smart rescheduling.

## Fundamentals
1. less than 1 second cold startup
2. it must not be possible in less clicks/steps
3. open source

## 🚀 MVP Features
- Add task: description, note, labels
- Tasks default to today
- Swipe right: reschedule to tomorrow, 2d, next week, next month
- Local DB: Hive or Isar
- <1s cold startup
- Unit and widget test coverage

## 🛠️ Getting Started

```bash
## on first install https://docs.flutter.dev/install
## install the flutter plugin in vscode

flutter pub get
flutter run -d chrome
flutter build apk --release #after installing the android SDK
```

When running the app on Chrome, swipe gestures can be hard to test.
Each task tile includes a **swipe** icon that performs the same action
as dragging the tile. Use this button to simulate a swipe when testing
in the browser.

## 🏗️ Building Releases
Run the helper script in the `tool` directory to build production
artifacts. The script automatically bumps the patch version and names
the build output with the version number.

```bash
sh tool/build.sh <platform>
# Example: sh tool/build.sh apk # for Android APK
```

For example `sh tool/build.sh web` will create a folder like
`build/web-0.1.4` containing the compiled app.

## Publishing
### Android
follow this tutorial to publish the app on the Play Store:
https://www.youtube.com/watch?v=ZxjgV1YaOcQ

```bash
flutter build appbundle --release
```

## Colors
Primary: rgba(0, 95, 221, 1)
## Issues

### build the android file
when you get issue with the android build, try to run
```bash
flutter create .
flutter pub get
```

### LogicalSize

if you get this
/C:/Users/noone/AppData/Local/Pub/Cache/hosted/pub.dev/home_widget-0.3.1/lib/home_widget.dart:137:11: 
Error: No named parameter with the name 'size'.
          size: logicalSize,
          ^^^^
/C:/dev/flutter/packages/flutter/lib/src/rendering/view.dart:33:9: Context: Found this candidate, but 
the arguments don't match.
  const ViewConfiguration({
        ^^^^^^^^^^^^^^^^^

just 
```bash
flutter clean
flutter pub get
flutter create .
flutter run
```
## Update icon

python ./tool/update_icon.py

## Build number
version in pubspec.yaml is:
<version_name>+<build_number>

So in:
version: 0.1.41+11
0.1.41 = human-facing app version (versionName on Android, CFBundleShortVersionString on iOS)
11 = internal build number (versionCode on Android, CFBundleVersion on iOS)
You increment +11 for each new store/build upload, even if the visible version stays the same.

im creating version 0.1.42, what should the buildnumber be?
Use +12 if your current released/uploaded build was +11.

So set:
version: 0.1.42+12

Rule of thumb: keep build number strictly increasing for every new build you distribute.