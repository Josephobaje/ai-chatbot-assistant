import 'dart:convert';
import 'dart:io';

import 'package:ai_assistant/src/chat_service.dart';
import 'package:ai_assistant/src/retriever.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final r = TfidfRetriever(parseMarkdownFaq(File('assets/business-faq.md').readAsStringSync()));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('offline answer and history persistence', () async {
    final s = ChatService(r, await SharedPreferences.getInstance());
    final m = await s.reply('What are your opening hours?');
    expect(m.source, 'offline');
    expect(m.text, contains('Monday to Saturday'));
    await s.saveHistory([ChatMessage(role: 'user', text: 'hi'), m]);
    expect(s.loadHistory().length, 2);
    await s.clearHistory();
    expect(s.loadHistory(), isEmpty);
  });

  test('uses backend when URL set', () async {
    final client = MockClient((req) async {
      expect(req.url.path, '/api/chat');
      return http.Response(jsonEncode({'session_id': 'x', 'reply': 'from server', 'provider': 'mock', 'sources': []}), 200);
    });
    final s = ChatService(r, await SharedPreferences.getInstance(), client: client);
    await s.setBackendUrl('http://10.0.2.2:8000/');
    final m = await s.reply('hi');
    expect(m.source, 'server');
    expect(m.text, 'from server');
  });

  test('falls back offline when backend fails', () async {
    final client = MockClient((_) async => http.Response('err', 500));
    final s = ChatService(r, await SharedPreferences.getInstance(), client: client);
    await s.setBackendUrl('http://bad');
    expect((await s.reply('how much is delivery')).source, 'offline');
  });
}
