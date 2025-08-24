import 'dart:async';
import 'package:flutter/foundation.dart';

/// An asynchronous variant of [ValueNotifier] that *coalesces* multiple value assignments within the same event‑loop turn into a single notification dispatched in a later microtask.
///
/// Key benefits:
/// * Avoids synchronous listener re‑entrancy corrupting sequential logic.
/// * Prevents common Flutter "setState()/markNeedsBuild during build" style exceptions by deferring callbacks until after the current stack unwinds.
/// * Optionally cancels notification if value reverted during the same event loop turn.
/// * Optionally ignores duplicate listeners while triggering.
/// * Supports weak-referenced listeners (to avoid memory leaks).
/// * Supports custom equality checks.
class AsyncValueNotifier<T> implements ValueListenable<T> {
  /// Default comparison function for [AsyncValueNotifier].
  static bool defaultIsEqual<T>(T a, T b) {
    if (a == b) {
      return true;
    } else if (a is double && b is double) {
      return a.isNaN && b.isNaN;
    }
    return false;
  }

  final _toAdd = <VoidCallback>[];
  final _toRemove = <VoidCallback, int>{};
  var _list = <VoidCallback>[];
  var _weakList = <_ListenerRef>[];
  var _expando = Expando<_ListenerRef>();
  var _pending = false;
  var _dispatching = false;
  var _disposed = false;
  T _value;

  /// Creates a new [AsyncValueNotifier] with the given [value].
  ///
  /// [cancelable] determines whether the notifier should suppress unchanged notifications.
  ///
  /// [distinct] determines whether the notifier should ignore duplicate listeners while triggering.
  AsyncValueNotifier(
    T value, {
    this.isEqual,
    this.distinct = false,
    this.cancelable = false,
    this.weakListener = false,
  }) : _value = value;

  /// Disposes the notifier and (eagerly) clears listeners.
  ///
  /// Safe to call multiple times; subsequent calls are no‑ops. Pending microtasks will observe `_disposed` and avoid notifying.
  void dispose() {
    if (!_disposed) {
      if (!_dispatching) {
        _clearListeners();
      }
      _toAdd.clear();
      _toRemove.clear();
      _disposed = true;
    }
  }

  /// Whether the notifier should use weak references for listeners. If true, listeners that are no longer strongly referenced elsewhere will be garbage collected and automatically removed.
  final bool weakListener;

  /// The comparison function used to determine if two values are equal.
  bool Function(T, T)? isEqual;

  /// Whether the notifier should ignore duplicate listeners while triggering.
  bool distinct;

  /// Whether the notifier should ignore unchanged notifications.
  bool cancelable;

  /// Whether the notifier is currently pending notification.
  bool get pending => _pending;

  /// Whether the notifier is currently dispatching notifications.
  bool get dispatching => _dispatching;

  /// Whether the notifier has been disposed.
  bool get disposed => _disposed;

  /// Returns a list of active listener callbacks.
  List<VoidCallback> get listeners {
    if (weakListener) {
      final it = _weakList.where((ref) => ref.target != null);
      final result =
          List<VoidCallback>.unmodifiable(it.map((ref) => ref.target!));
      if (!_dispatching && result.length != _weakList.length) {
        _weakList = it.toList();
      }
      return result;
    } else {
      return List.unmodifiable(_list);
    }
  }

  /// Assigns a new value.
  ///
  /// Behavior:
  /// * The first *distinct* assignment in a turn schedules a microtask; later assignments in the same turn simply update [value] (only the final value is observed by listeners).
  /// * On microtask execution we re‑check disposal and (if [cancelable]) whether the value reverted; if reverted, we skip notifying.
  /// * [value] is updated *before* scheduling completes, so synchronous reads after the setter see the new value even though listeners have not run.
  set value(T newValue) {
    if (!_disposed && !_isEqual(newValue)) {
      if (!_pending) {
        _pending = true;
        final oldValue = _value;
        // Future.microtask() is not suitable here cause it has own error handling logic.
        scheduleMicrotask(() {
          _pending = false;
          if (!_disposed && (!cancelable || !_isEqual(oldValue))) {
            _dispatching = true;
            final distinctListeners = <VoidCallback>{};
            if (weakListener) {
              var gced = false;
              for (final ref in _weakList) {
                if (_disposed) {
                  break;
                }
                final listener = ref.target;
                if (listener == null) {
                  gced = true;
                } else if (distinctListeners.add(listener) || !distinct) {
                  _runListener(listener);
                }
              }
              _dispatching = false;
              if (_disposed) {
                _clearListeners();
              } else if (!gced && _toRemove.isEmpty) {
                for (final listener in _toAdd) {
                  _addRef(listener, _expando, _weakList);
                }
              } else {
                final newList = <_ListenerRef>[];
                final newExpando = Expando<_ListenerRef>();
                for (final ref in _weakList) {
                  final listener = ref.target;
                  if (listener != null && _needAdd(listener)) {
                    if (newExpando[listener] == null) {
                      newExpando[listener] = ref;
                      ref.count = 1;
                    } else {
                      ref.count++;
                    }
                    newList.add(ref);
                  }
                }
                for (final listener in _toAdd) {
                  if (_needAdd(listener)) {
                    _addRef(listener, newExpando, newList);
                  }
                }
                _toAdd.clear();
                _toRemove.clear();
                _weakList = newList;
                _expando = newExpando;
              }
            } else {
              for (final listener in _list) {
                if (_disposed) {
                  break;
                }
                if (distinctListeners.add(listener) || !distinct) {
                  _runListener(listener);
                }
              }
              _dispatching = false;
              if (_disposed) {
                _clearListeners();
              } else if (_toRemove.isEmpty) {
                for (final listener in _toAdd) {
                  _list.add(listener);
                }
              } else {
                final newList = <VoidCallback>[];
                for (final listener in _list) {
                  if (_needAdd(listener)) {
                    newList.add(listener);
                  }
                }
                for (final listener in _toAdd) {
                  if (_needAdd(listener)) {
                    newList.add(listener);
                  }
                }
                _toAdd.clear();
                _toRemove.clear();
                _list = newList;
              }
            }
          }
        });
      }
      _value = newValue;
    }
  }

  @override
  T get value => _value;

  /// Register a closure to be called when the object notifies its listeners. This operation takes effect while [dispatching] is false.
  @override
  void addListener(VoidCallback listener) => _setListener(listener, true);

  /// Unregisters a closure so it will no longer be called when the object notifies its listeners. This operation takes effect while [dispatching] is false.
  @override
  void removeListener(VoidCallback listener) => _setListener(listener, false);

  @override
  String toString() => '${describeIdentity(this)}($_value)';

  bool _isEqual(T other) =>
      isEqual?.call(_value, other) ?? defaultIsEqual(_value, other);

  void _setListener(VoidCallback listener, bool add) {
    if (!_disposed) {
      if (_dispatching) {
        if (add) {
          _toAdd.add(listener);
        } else {
          _toRemove[listener] = (_toRemove[listener] ?? 0) + 1;
        }
      }
      if (weakListener) {
        if (add) {
          _addRef(listener, _expando, _weakList);
        } else {
          var ref = _expando[listener];
          if (ref != null) {
            _weakList.remove(ref);
            if (--ref.count == 0) {
              _expando[listener] = null;
            }
          }
        }
      } else if (add) {
        _list.add(listener);
      } else {
        _list.remove(listener);
      }
    }
  }

  void _clearListeners() {
    if (weakListener) {
      for (final ref in _weakList) {
        if (ref.target != null) {
          _expando[ref.target!] = null;
        }
      }
      _weakList.clear();
    } else {
      _list.clear();
    }
  }

  void _addRef(
    VoidCallback listener,
    Expando<_ListenerRef> expando,
    List<_ListenerRef> list,
  ) {
    var ref = expando[listener];
    if (ref == null) {
      ref = _ListenerRef(listener);
      expando[listener] = ref;
    }
    ref.count++;
    list.add(ref);
  }

  bool _needAdd(VoidCallback listener) {
    final del = _toRemove[listener];
    if (del != null && del > 0) {
      _toRemove[listener] = del - 1;
      return false;
    }
    return true;
  }

  // Allow subsequent listeners to run even if one throws while preserving uncaught exception propagation for debugging.
  @pragma('vm:notify-debugger-on-exception')
  void _runListener(VoidCallback listener) {
    try {
      listener();
    } catch (e, s) {
      if (!kDebugMode) {
        FlutterError.reportError(FlutterErrorDetails(
          exception: e,
          stack: s,
          library: 'async_value_notifier',
          informationCollector: () => <DiagnosticsNode>[
            DiagnosticsProperty<VoidCallback>('listener', listener),
            DiagnosticsProperty<AsyncValueNotifier>('AsyncValueNotifier', this),
          ],
        ));
      }
    }
  }
}

class _ListenerRef {
  final WeakReference<VoidCallback> _value;
  var count = 0;
  _ListenerRef(VoidCallback listener) : _value = WeakReference(listener);

  VoidCallback? get target => _value.target;
}
