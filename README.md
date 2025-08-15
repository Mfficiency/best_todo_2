# Best To-Do 2

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
flutter pub get
flutter run -d chrome
flutter build apk --release
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
flutter run
```
## Update icon

python ./tool/update_icon.py