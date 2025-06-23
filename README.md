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

```

When running the app on Chrome, swipe gestures can be hard to test.
Each task tile includes a **swipe** icon that performs the same action
as dragging the tile. Use this button to simulate a swipe when testing
in the browser.