import 'dart:async';
import 'package:flutter/material.dart';
import 'package:async_value_notifier/async_value_notifier.dart';

void main() => runApp(const DemoApp());

enum TaskStatus { ready, running, ended }

class LogBuffer {
  final _logs = <String>[];
  final logsNotifier = ValueNotifier<int>(0); // trigger UI rebuild

  List<String> get logs => List.unmodifiable(_logs);

  void add(String line) {
    // Use only the time part for brevity
    final ts = DateTime.now().toIso8601String().split('T').last;
    _logs.add('[$ts] $line');
    if (_logs.length > 200) _logs.removeRange(0, _logs.length - 200);
    logsNotifier.value++;
    // Also print to console
    // ignore: avoid_print
    print(line);
  }

  void clear() {
    _logs.clear();
    logsNotifier.value++;
  }
}

final log = LogBuffer();

/// Using a normal ValueNotifier: listeners fire synchronously.
/// This allows code inserted by listeners to override state changes that happen later in the same sequential logic.
class TaskControllerSync {
  final status = ValueNotifier(TaskStatus.ready);
  final errorCode = ValueNotifier<int?>(null);

  TaskControllerSync() {
    errorCode.addListener(() {
      if (errorCode.value != null) {
        log.add('[sync] error listener: set status -> ready (to allow retry)');
        status.value = TaskStatus.ready; // will be overwriten
      }
    });
  }

  Future<void> startTask() async {
    if (status.value != TaskStatus.ready) {
      log.add('[sync] task is not ready');
      return;
    }
    errorCode.value = null;
    log.add('[sync] start task');
    status.value = TaskStatus.running;
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      throw Exception('network error');
    } catch (e) {
      log.add('[sync] set errorCode');
      errorCode.value = 500; // triggers listener immediately
    }
    log.add('[sync] set status -> ended');
    status.value = TaskStatus.ended; // overwrites listener ready
  }
}

/// Using AsyncValueNotifier: listener notifications are batched in a microtask.
/// Sequential logic completes first; listeners run afterward, avoiding mid-flow interference.
class TaskControllerAsync {
  final status = AsyncValueNotifier(TaskStatus.ready);
  final errorCode = AsyncValueNotifier<int?>(null);

  TaskControllerAsync() {
    errorCode.addListener(() {
      if (errorCode.value != null) {
        log.add('[async] error listener: set status -> ready (to allow retry)');
        status.value = TaskStatus.ready; // Final state will be ready
      }
    });
  }

  Future<void> startTask() async {
    if (status.value != TaskStatus.ready) {
      log.add('[async] task is not ready');
      return;
    }
    errorCode.value = null;
    log.add('[async] start task');
    status.value = TaskStatus.running;
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      throw Exception('network error');
    } catch (e) {
      log.add('[async] set errorCode');
      errorCode.value = 500; // listener not triggered yet
    }
    log.add('[async] set status -> ended');
    status.value = TaskStatus.ended; // before notifying listeners
  }
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AsyncValueNotifier Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final TaskControllerSync syncCtrl;
  late final TaskControllerAsync asyncCtrl;

  @override
  void initState() {
    super.initState();
    syncCtrl = TaskControllerSync();
    asyncCtrl = TaskControllerAsync();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AsyncValueNotifier vs ValueNotifier')),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Demo: task fails -> set error code -> set status to ended. Error listener tries to reset status to ready for retry.',
                  ),
                  const SizedBox(height: 12),
                  _SectionTitle('1. Synchronous ValueNotifier (problematic)'),
                  _SyncStatusView(ctrl: syncCtrl),
                  const SizedBox(height: 8),
                  _SectionTitle('2. AsyncValueNotifier (works as intended)'),
                  _AsyncStatusView(ctrl: asyncCtrl),
                  const Divider(height: 32),
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          log.clear();
                          syncCtrl.startTask();
                        },
                        child: const Text('Run sync task'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () {
                          log.clear();
                          asyncCtrl.startTask();
                        },
                        child: const Text('Run async task'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Logs (newest first):'),
                  ValueListenableBuilder(
                    valueListenable: log.logsNotifier,
                    builder: (_, __, ___) {
                      final lines = log.logs.reversed.toList();
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: SelectableText(
                          lines.join('\n'),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: Colors.greenAccent,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncStatusView extends StatelessWidget {
  final TaskControllerSync ctrl;
  const _SyncStatusView({required this.ctrl});

  String _statusText(TaskStatus s) => s.name;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ValueListenableBuilder(
          valueListenable: ctrl.status,
          builder: (_, s, __) => Chip(
            label: Text('status: ${_statusText(s)}'),
            backgroundColor: Colors.red.withValues(alpha: 0.1),
          ),
        ),
        const SizedBox(width: 8),
        ValueListenableBuilder(
          valueListenable: ctrl.errorCode,
          builder: (_, e, __) => Chip(
            label: Text('error: ${e ?? '-'}'),
            backgroundColor: Colors.orange.withValues(alpha: 0.15),
          ),
        ),
      ],
    );
  }
}

class _AsyncStatusView extends StatelessWidget {
  final TaskControllerAsync ctrl;
  const _AsyncStatusView({required this.ctrl});

  String _statusText(TaskStatus s) => s.name;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ValueListenableBuilder<TaskStatus>(
          valueListenable: ctrl.status,
          builder: (_, s, __) => Chip(
            label: Text('status: ${_statusText(s)}'),
            backgroundColor: Colors.green.withValues(alpha: 0.15),
          ),
        ),
        const SizedBox(width: 8),
        ValueListenableBuilder<int?>(
          valueListenable: ctrl.errorCode,
          builder: (_, e, __) => Chip(
            label: Text('error: ${e ?? '-'}'),
            backgroundColor: Colors.blue.withValues(alpha: 0.15),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}
