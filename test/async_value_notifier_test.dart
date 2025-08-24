import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker/leak_tracker.dart';
import 'package:async_value_notifier/async_value_notifier.dart';

void main() {
  group('AsyncValueNotifier', () {
    test('coalesces multiple sets in same turn and notifies once', () async {
      final n = AsyncValueNotifier(0);
      final calls = <int>[];
      n.addListener(() => calls.add(n.value));

      // Same event loop turn: schedule no microtasks yet.
      n.value = 1;
      n.value = 2;
      n.value = 3;

      // Synchronous read sees latest value immediately.
      expect(n.value, 3);
      // No notification yet until microtask runs.
      expect(calls, isEmpty);

      // Let microtasks flush.
      await Future<void>.delayed(Duration.zero);

      expect(calls, [3]);
    });

    test('cancelable=true skips notification if value reverted', () async {
      final n = AsyncValueNotifier(0, cancelable: true);
      var count = 0;
      n.addListener(() => count++);

      n.value = 1; // schedule
      n.value = 0; // revert within same turn

      await Future<void>.delayed(Duration.zero);

      expect(count, 0);
      expect(n.value, 0);
    });

    test('distinct avoids duplicate listener callbacks within one dispatch',
        () async {
      final n = AsyncValueNotifier(0, distinct: true);
      var count = 0;
      void listener() => count++;
      n.addListener(listener);
      // Intentionally add the same closure multiple times
      n.addListener(listener);
      n.addListener(listener);

      n.value = 1;
      await Future<void>.delayed(Duration.zero);

      expect(count, 1);
    });

    test('custom isEqual prevents notifications for semantic equality',
        () async {
      // Treat odd/even parity equal.
      bool eq(int a, int b) => (a % 2) == (b % 2);
      final n = AsyncValueNotifier(0, isEqual: eq);
      var fired = 0;
      n.addListener(() => fired++);

      n.value = 2; // equal by parity => no notify and no value update
      n.value = 4; // equal => still no notify and value unchanged

      await Future<void>.delayed(Duration.zero);

      expect(fired, 0);
      expect(n.value, 0);

      n.value = 5; // parity changed 0/4 -> 5 => notify once
      await Future<void>.delayed(Duration.zero);
      expect(fired, 1);
      expect(n.value, 5);
    });

    test('weakListener removes GC-ed listeners and keeps live ones', () async {
      final n = AsyncValueNotifier(0, weakListener: true);

      var strongCount = 0;
      var weakCount = 0;

      // Create GC-eligible listeners.
      final listeners = [
        () => strongCount++,
        () => weakCount++,
      ];

      n.addListener(listeners[0]);
      n.addListener(listeners[1]);

      expect(n.listeners.length, 2);

      // Drop our reference and force GC.
      listeners.removeAt(1);
      await forceGC();

      expect(n.listeners.length, 1);

      n.value = 1;
      await Future<void>.delayed(Duration.zero);

      expect(strongCount, 1);
      expect(weakCount, 0);
    });

    test('exceptions from one listener do not prevent others (release path)',
        () async {
      final n = AsyncValueNotifier(0);
      final calls = <String>[];

      // A listener that throws.
      void bad() => throw StateError('boom');
      // A normal listener should still run.
      void good() => calls.add('good');

      // In debug mode, exceptions propagate. We mimic release behavior by
      // catching around the microtask to ensure both listeners attempted.
      runZonedGuarded(() {
        n.addListener(bad);
        n.addListener(good);
        n.value = 1;
      }, (e, s) {
        // swallow for test to proceed
      });

      await Future<void>.delayed(Duration.zero);

      expect(calls, ['good']);
    });

    test('dispose prevents further notifications and clears listeners',
        () async {
      final n = AsyncValueNotifier(0);
      var count = 0;
      void l() => count++;
      n.addListener(l);

      n.dispose();
      n.value = 1; // set after dispose should not notify

      await Future<void>.delayed(Duration.zero);

      expect(count, 0);
      expect(n.disposed, isTrue);
    });
  });
}
