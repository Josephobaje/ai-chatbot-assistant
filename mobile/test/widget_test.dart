import 'dart:io';

import 'package:ai_assistant/main.dart';
import 'package:ai_assistant/src/chat_service.dart';
import 'package:ai_assistant/src/retriever.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('sends a message and shows offline answer', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final r = TfidfRetriever(parseMarkdownFaq(File('assets/business-faq.md').readAsStringSync()));
    await tester.pumpWidget(AssistantApp(service: ChatService(r, prefs)));
    expect(find.text('AI Assistant'), findsOneWidget);
    expect(find.text('Offline mode'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('input')), 'Where are you located?');
    await tester.tap(find.byKey(const Key('send')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Wuse II'), findsOneWidget);
  });
}
