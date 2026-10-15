import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'retriever.dart';

class ChatMessage {
  ChatMessage({required this.role, required this.text, this.source, DateTime? at})
      : at = at ?? DateTime.now();
  final String role; // 'user' | 'assistant'
  final String text;
  final String? source; // 'offline' | 'server'
  final DateTime at;

  bool get isUser => role == 'user';

  Map<String, dynamic> toJson() =>
      {'role': role, 'text': text, 'source': source, 'at': at.toIso8601String()};

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        role: j['role'] as String,
        text: j['text'] as String,
        source: j['source'] as String?,
        at: DateTime.tryParse(j['at'] as String? ?? ''),
      );
}

/// Answers messages offline, or via the FastAPI backend when a URL is set.
class ChatService {
  ChatService(this.retriever, this.prefs, {http.Client? client})
      : _client = client ?? http.Client();

  static const historyKey = 'chat_history';
  static const urlKey = 'backend_url';
  static const maxHistory = 200;

  final TfidfRetriever retriever;
  final SharedPreferences prefs;
  final http.Client _client;
  String? _sessionId;

  String get backendUrl => prefs.getString(urlKey) ?? '';
  Future<void> setBackendUrl(String url) => prefs.setString(urlKey, url.trim());

  List<ChatMessage> loadHistory() {
    final raw = prefs.getString(historyKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveHistory(List<ChatMessage> msgs) {
    final keep = msgs.length > maxHistory ? msgs.sublist(msgs.length - maxHistory) : msgs;
    return prefs.setString(historyKey, jsonEncode(keep.map((m) => m.toJson()).toList()));
  }

  Future<void> clearHistory() async {
    _sessionId = null;
    await prefs.remove(historyKey);
  }

  Future<ChatMessage> reply(String message) async {
    final url = backendUrl;
    if (url.isNotEmpty) {
      try {
        final base = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
        final res = await _client
            .post(Uri.parse('$base/api/chat'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({'message': message, 'session_id': _sessionId}))
            .timeout(const Duration(seconds: 12));
        if (res.statusCode == 200) {
          final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
          _sessionId = j['session_id'] as String?;
          return ChatMessage(role: 'assistant', text: j['reply'] as String, source: 'server');
        }
      } catch (_) {
        // fall through to offline answer
      }
    }
    final hits = retriever.search(message);
    return ChatMessage(role: 'assistant', text: offlineReply(message, hits), source: 'offline');
  }
}
