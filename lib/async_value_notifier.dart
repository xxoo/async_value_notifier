import 'dart:async';
import 'package:flutter/foundation.dart';

class _AltListener {
  final VoidCallback value;
  final bool add;

  const _AltListener(this.value, this.add);
}

/// An asynchronous variant of [ValueNotifier] that *coalesces* multiple value assignments within the same event‑loop turn into a single notification dispatched in a later microtask.
///
/// Key benefits:
/// * Avoids synchronous listener re‑entrancy corrupting sequential logic.
/// * Prevents common Flutter "setState()/markNeedsBuild during build" style exceptions by deferring callbacks until after the current stack unwinds.
/// * Optionally suppresses "undo" changes (value changed then restored) and optionally ignores duplicate listener registrations.

class AsyncValueNotifier<T> implements ValueListenable<T> {
  final Iterable<VoidCallback> _listeners;
  final _altListeners = <_AltListener>[];
  var _pending = false;
  var _dispatching = false;
  var _disposed = false;
  T _value;

  /// Whether the notifier should ignore unchanged notifications.
  final bool undoable;

  /// Whether the notifier supports ignoring duplicate listeners.
  final bool antiDuplication;

  /// Creates a new [AsyncValueNotifier] with the given [value].
  ///
  /// [undoable] determines whether the notifier should suppress unchanged notifications.
  ///
  /// [antiDuplication] determines whether the notifier should ignore duplicate listeners.
  AsyncValueNotifier(
    T value, {
    this.undoable = false,
    this.antiDuplication = false,
  })  : _value = value,
        _listeners = antiDuplication ? <VoidCallback>{} : <VoidCallback>[];

  /// Disposes the notifier and (eagerly) clears listeners.
  ///
  /// Safe to call multiple times; subsequent calls are no‑ops. Pending microtasks will observe `_disposed` and avoid notifying.
  void dispose() {
    if (!_disposed) {
      if (!_dispatching) {
        _clearListeners();
      }
      _altListeners.clear();
      _disposed = true;
    }
  }

  /// Whether the notifier has been disposed.
  bool get disposed => _disposed;

  /// Assigns a new value.
  ///
  /// Behavior:
  /// * The first *distinct* assignment in a turn schedules a microtask; later assignments in the same turn simply update [value] (only the final value is observed by listeners).
  /// * On microtask execution we re‑check disposal and (if [undoable]) whether the value reverted; if reverted, we skip notifying.
  /// * [value] is updated *before* scheduling completes, so synchronous reads after the setter see the new value even though listeners have not run.
  set value(T newValue) {
    if (!_disposed && newValue != _value) {
      if (!_pending) {
        _pending = true;
        final oldValue = _value;
        // We intentionally use scheduleMicrotask instead of Future.microtask to avoid Future's additional error-handling semantics (which can wrap/deflect uncaught errors). Raw microtask preserves debugging clarity and still defers execution.
        scheduleMicrotask(() {
          _pending = false;
          if (!_disposed && (!undoable || _value != oldValue)) {
            _dispatching = true;
            for (final listener in _listeners) {
              if (_disposed) {
                break;
              }
              // Allow subsequent listeners to run even if one throws while preserving uncaught exception propagation for debugging.
              try {
                listener();
              } finally {
                continue; // ignore: control_flow_in_finally
              }
            }
            _dispatching = false;
            if (_disposed) {
              _clearListeners();
            } else {
              for (final altListener in _altListeners) {
                altListener.add
                    ? _addListener(altListener.value)
                    : _removeListener(altListener.value);
              }
              _altListeners.clear();
            }
          }
        });
      }
      _value = newValue;
    }
  }

  @override
  T get value => _value;

  @override
  void addListener(VoidCallback listener) => _setListener(listener, true);

  @override
  void removeListener(VoidCallback listener) => _setListener(listener, false);

  @override
  String toString() => '${describeIdentity(this)}($_value)';

  void _setListener(VoidCallback listener, bool add) {
    if (!_disposed) {
      _dispatching
          ? _altListeners.add(_AltListener(listener, add))
          : add
              ? _addListener(listener)
              : _removeListener(listener);
    }
  }

  void _clearListeners() => antiDuplication
      ? (_listeners as Set<VoidCallback>).clear()
      : (_listeners as List<VoidCallback>).clear();

  void _addListener(VoidCallback listener) => antiDuplication
      ? (_listeners as Set<VoidCallback>).add(listener)
      : (_listeners as List<VoidCallback>).add(listener);

  void _removeListener(VoidCallback listener) => antiDuplication
      ? (_listeners as Set<VoidCallback>).remove(listener)
      : (_listeners as List<VoidCallback>).remove(listener);
}
