import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import 'src/chat_service.dart';
import 'src/retriever.dart';

const navy = Color(0xFF0B1F3A);
const accent = Color(0xFF2F80ED);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final md = await rootBundle.loadString('assets/business-faq.md');
  final prefs = await SharedPreferences.getInstance();
  runApp(AssistantApp(service: ChatService(TfidfRetriever(parseMarkdownFaq(md)), prefs)));
}

class AssistantApp extends StatelessWidget {
  const AssistantApp({super.key, required this.service});
  final ChatService service;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Assistant',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: accent, primary: navy),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: ChatScreen(service: service),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.service});
  final ChatService service;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  late List<ChatMessage> _msgs;
  bool _busy = false;

  static const suggestions = [
    'What are your opening hours?',
    'How long does delivery take?',
    'Can I return a product?',
    'What payment methods do you accept?',
  ];

  @override
  void initState() {
    super.initState();
    _msgs = widget.service.loadHistory();
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _ctrl.text).trim();
    if (text.isEmpty || _busy) return;
    _ctrl.clear();
    setState(() {
      _msgs.add(ChatMessage(role: 'user', text: text));
      _busy = true;
    });
    _toBottom();
    final r = await widget.service.reply(text);
    if (!mounted) return;
    setState(() {
      _msgs.add(r);
      _busy = false;
    });
    await widget.service.saveHistory(_msgs);
    _toBottom();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _openSettings() async {
    final c = TextEditingController(text: widget.service.backendUrl);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Settings'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Optional backend URL (FastAPI server). Leave empty to work fully offline.'),
          const SizedBox(height: 12),
          TextField(
            key: const Key('urlField'),
            controller: c,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(hintText: 'https://your-server.com', border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved == true) {
      await widget.service.setBackendUrl(c.text);
      if (mounted) setState(() {});
    }
  }

  Future<void> _clear() async {
    await widget.service.clearHistory();
    setState(() => _msgs = []);
  }

  @override
  Widget build(BuildContext context) {
    final online = widget.service.backendUrl.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        title: Row(children: [
          const CircleAvatar(radius: 16, backgroundColor: accent, child: Icon(Icons.smart_toy, size: 18, color: Colors.white)),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('AI Assistant', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            Text(online ? 'Server mode' : 'Offline mode', style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ]),
        ]),
        actions: [
          IconButton(tooltip: 'Clear chat', icon: const Icon(Icons.delete_outline), onPressed: _clear),
          IconButton(tooltip: 'Settings', icon: const Icon(Icons.settings), onPressed: _openSettings),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: _msgs.isEmpty
              ? _Welcome(onPick: _send)
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(12),
                  itemCount: _msgs.length + (_busy ? 1 : 0),
                  itemBuilder: (_, i) => i == _msgs.length
                      ? const _Bubble(text: 'Typing…', isUser: false)
                      : _Bubble(text: _msgs[i].text, isUser: _msgs[i].isUser),
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 10),
            child: Row(children: [
              Expanded(
                child: TextField(
                  key: const Key('input'),
                  controller: _ctrl,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: 'Ask a question…',
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(key: const Key('send'), onPressed: _send, icon: const Icon(Icons.send)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onPick});
  final void Function(String) onPick;

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(24), children: [
      const SizedBox(height: 24),
      const Icon(Icons.smart_toy, size: 64, color: accent),
      const SizedBox(height: 12),
      Text('How can I help you today?', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 6),
      const Text('Answers come from the business FAQ, even with no internet.', textAlign: TextAlign.center),
      const SizedBox(height: 20),
      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
        for (final s in _ChatScreenState.suggestions) ActionChip(label: Text(s), onPressed: () => onPick(s)),
      ]),
      const SizedBox(height: 32),
      const Text('Built by Joseph Obaje', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12)),
    ]);
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.isUser});
  final String text;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? accent : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Text(text, style: TextStyle(color: isUser ? Colors.white : cs.onSurface, height: 1.35)),
      ),
    );
  }
}
