import 'dart:io';

import 'package:ai_assistant/src/retriever.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final docs = parseMarkdownFaq(File('assets/business-faq.md').readAsStringSync());
  final r = TfidfRetriever(docs);

  test('parses all FAQ entries', () => expect(docs.length, 10));
  test('tokenizer stems and drops stopwords', () {
    expect(tokenize('How do deliveries work?'), ['delivery', 'work']);
  });
  test('finds delivery time', () {
    expect(r.search('how long will delivery take').first.doc.question, 'How long does delivery take?');
  });
  test('finds returns', () {
    expect(r.search('I want to return my item').first.doc.question, 'Can I return a product?');
  });
  test('unknown question falls back politely', () {
    expect(offlineReply('quantum physics', r.search('quantum physics')), contains("don't have an answer"));
  });
  test('greeting', () => expect(offlineReply('hello', const []), startsWith('Hello')));
}
