## About

`AsyncValueNotifier` is an asynchronous variant of [`ValueNotifier`](https://api.flutter.dev/flutter/foundation/ValueNotifier-class.html) that *coalesces* multiple value assignments within the same event‑loop turn into a single notification dispatched in a later microtask.

Key benefits:
* Avoids synchronous listener re‑entrancy corrupting sequential logic.
* Prevents common Flutter "setState()/markNeedsBuild during build" style exceptions by deferring callbacks until after the current stack unwinds.
* Optionally suppresses "undo" changes (value changed then restored) and optionally ignores duplicate listener registrations.

## Installation

1. Run the following command in your project directory:
```shell
flutter pub add async_value_notifier
```
2. Add the following code to your dart file:
```dart
import 'package:async_value_notifier/async_value_notifier.dart';
```

## Usage
Almost the same as [`ValueNotifier`](https://api.flutter.dev/flutter/foundation/ValueNotifier-class.html). For more information, please check [example](https://pub.dev/packages/async_value_notifier/example) or [API reference](https://pub.dev/documentation/async_value_notifier/latest/async_value_notifier/AsyncValueNotifier-class.html).