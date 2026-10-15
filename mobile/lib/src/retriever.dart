import 'dart:math' as math;

/// A question/answer entry from the markdown FAQ knowledge base.
class FaqDoc {
  const FaqDoc(this.question, this.answer);
  final String question;
  final String answer;
}

class Hit {
  const Hit(this.doc, this.score);
  final FaqDoc doc;
  final double score;
}

const _stopwords = {
  'a', 'an', 'and', 'are', 'as', 'at', 'be', 'by', 'can', 'do', 'does', 'for',
  'from', 'how', 'i', 'in', 'is', 'it', 'me', 'my', 'of', 'on', 'or', 'our',
  'please', 'the', 'to', 'we', 'what', 'when', 'where', 'which', 'who', 'why',
  'will', 'with', 'you', 'your', 'yours',
};

/// Same tokenizer as the Python backend (app/retrieval.py).
List<String> tokenize(String text) {
  final out = <String>[];
  for (final m in RegExp(r'[a-z0-9₦]+').allMatches(text.toLowerCase())) {
    var w = m.group(0)!;
    if (_stopwords.contains(w)) continue;
    for (final suf in const ['ies', 'es', 's', 'ing', 'ed']) {
      if (w.length > 4 && w.endsWith(suf)) {
        w = w.substring(0, w.length - suf.length) + (suf == 'ies' ? 'y' : '');
        break;
      }
    }
    out.add(w);
  }
  return out;
}

/// Parses "## Question\nAnswer" markdown blocks.
List<FaqDoc> parseMarkdownFaq(String md) {
  final docs = <FaqDoc>[];
  for (final block in md.split(RegExp(r'^##\s+', multiLine: true))) {
    final lines = block.trim().split('\n');
    if (lines.length < 2) continue;
    final answer = lines.skip(1).map((l) => l.trim()).where((l) => l.isNotEmpty).join(' ');
    docs.add(FaqDoc(lines.first.trim(), answer));
  }
  return docs;
}

/// Dependency-free TF-IDF retriever (port of the backend retriever).
class TfidfRetriever {
  TfidfRetriever(this.docs) {
    final tokenized = [
      for (final d in docs) tokenize('${d.question} ${d.question} ${d.answer}')
    ];
    final n = docs.length;
    final df = <String, int>{};
    for (final toks in tokenized) {
      for (final t in toks.toSet()) {
        df[t] = (df[t] ?? 0) + 1;
      }
    }
    df.forEach((t, c) => _idf[t] = math.log((1 + n) / (1 + c)) + 1);
    _vectors = [for (final t in tokenized) _vec(t)];
  }

  final List<FaqDoc> docs;
  final Map<String, double> _idf = {};
  late final List<Map<String, double>> _vectors;

  Map<String, double> _vec(List<String> toks) {
    final tf = <String, int>{};
    for (final t in toks) {
      tf[t] = (tf[t] ?? 0) + 1;
    }
    final v = {for (final e in tf.entries) e.key: e.value * (_idf[e.key] ?? 0.0)};
    var norm = math.sqrt(v.values.fold<double>(0, (s, x) => s + x * x));
    if (norm == 0) norm = 1;
    return v.map((k, x) => MapEntry(k, x / norm));
  }

  List<Hit> search(String query, {int k = 3}) {
    final q = _vec(tokenize(query));
    final scored = <Hit>[];
    for (var i = 0; i < docs.length; i++) {
      var s = 0.0;
      q.forEach((t, w) => s += w * (_vectors[i][t] ?? 0.0));
      scored.add(Hit(docs[i], s));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(k).where((h) => h.score > 0).toList();
  }
}

/// Builds an offline reply from retrieval hits.
String offlineReply(String message, List<Hit> hits) {
  final greet = RegExp(r'^\s*(hi|hello|hey|good (morning|afternoon|evening))\b', caseSensitive: false);
  if (greet.hasMatch(message)) {
    return 'Hello! I can answer questions about opening hours, delivery, payments, returns and support. What would you like to know?';
  }
  if (hits.isEmpty || hits.first.score < 0.12) {
    return "Sorry, I don't have an answer for that yet. Try asking about delivery, payments, returns, opening hours or how to contact support.";
  }
  return hits.first.doc.answer;
}
