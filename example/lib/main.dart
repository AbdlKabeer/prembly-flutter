import 'package:flutter/material.dart';
import 'package:prembly/prembly.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Prembly example',
    theme: ThemeData(
      colorSchemeSeed: const Color(0xFF2D9D92),
      useMaterial3: true,
    ),
    home: const HomePage(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _key = TextEditingController(text: 'test_pk_xxxxxxxx');
  final _workflowId = TextEditingController();
  final _sessionId = TextEditingController();
  final _log = <String>[];
  bool _ready = false;

  void _say(String line) => setState(() => _log.insert(0, line));

  void _init() {
    try {
      Prembly.init(publishableKey: _key.text, debug: true);
      setState(() => _ready = true);
      _say('init ok: ${Prembly.environment?.name} (SDK ${Prembly.version})');
    } on PremblyError catch (e) {
      _say('init failed: ${e.code.wire}: ${e.message}');
    }
  }

  Future<void> _startWorkflow() async {
    try {
      await Prembly.workflow.start(
        context: context,
        workflowId: _workflowId.text.trim(),
        customer: const WorkflowCustomer(
          firstName: 'Ada',
          lastName: 'Obi',
          email: 'ada@example.com',
        ),
        onEvent: (e) =>
            _say('event: ${e.type}${e.nodeId == null ? '' : ' (${e.nodeId})'}'),
        callback: (r) => _say('callback: $r'),
      );
    } on PremblyError catch (e) {
      _say('start failed: ${e.code.wire}: ${e.message}');
    }
  }

  void _openSession() {
    try {
      Prembly.workflow.open(
        context: context,
        sessionId: _sessionId.text.trim(),
        onEvent: (e) => _say('event: ${e.type}'),
        callback: (r) => _say('callback: $r'),
      );
    } on PremblyError catch (e) {
      _say('open failed: ${e.code.wire}: ${e.message}');
    }
  }

  Future<void> _deviceSession() async {
    Prembly.tm.identify('customer-123');
    final session = await Prembly.tm.getDeviceSession(forceRefresh: true);
    _say('device session: $session');
  }

  Future<void> _signals() async {
    final signals = await Prembly.tm.getSignalsPreview();
    _say('signals: ${signals ?? 'none'}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Prembly example')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _key,
            decoration: const InputDecoration(labelText: 'Publishable key'),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _init, child: const Text('Prembly.init')),
          const Divider(height: 32),
          TextField(
            controller: _workflowId,
            decoration: const InputDecoration(labelText: 'Workflow ID (wf_…)'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _ready ? _startWorkflow : null,
            child: const Text('workflow.start'),
          ),
          TextField(
            controller: _sessionId,
            decoration: const InputDecoration(
              labelText: 'Session ID (from your backend)',
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _ready ? _openSession : null,
            child: const Text('workflow.open'),
          ),
          const Divider(height: 32),
          FilledButton(
            onPressed: _ready ? _deviceSession : null,
            child: const Text('tm.getDeviceSession'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _ready ? _signals : null,
            child: const Text('tm.getSignalsPreview'),
          ),
          const Divider(height: 32),
          for (final line in _log)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: SelectableText(line),
            ),
        ],
      ),
    );
  }
}
