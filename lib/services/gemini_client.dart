import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/appraisal.dart';
import 'prompt.dart';

class GeminiException implements Exception {
  final String message;
  GeminiException(this.message);
  @override
  String toString() => message;
}

class PhotoInput {
  final String label;
  final Uint8List bytes;
  final String mimeType;
  const PhotoInput(this.label, this.bytes, {this.mimeType = 'image/jpeg'});
}

class GeminiClient {
  static const _base = 'https://generativelanguage.googleapis.com/v1beta';
  final http.Client _http;
  final String apiKey;

  GeminiClient(this.apiKey, {http.Client? client})
      : _http = client ?? http.Client();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey,
      };

  /// Elenca i modelli disponibili per la chiave e sceglie il migliore.
  Future<String> resolveModel() async {
    final res = await _http
        .get(Uri.parse('$_base/models?pageSize=200'), headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw GeminiException(_explain(res));
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
    final list = (body['models'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final best = pickBestModel(list);
    if (best == null) {
      throw GeminiException(
          'Nessun modello Gemini adatto trovato per questa chiave.');
    }
    return best;
  }

  Future<WatchAppraisal> appraise({
    required String model,
    required List<PhotoInput> photos,
    String extraInfo = '',
    bool box = false,
    bool papers = false,
    bool webSearch = true,
  }) async {
    try {
      return await _appraise(model, photos, extraInfo, box, papers, webSearch);
    } on GeminiException catch (e) {
      // Se la ricerca web non è disponibile sul piano/modello, riprova senza.
      if (webSearch && e.message.contains('[tool]')) {
        return _appraise(model, photos, extraInfo, box, papers, false);
      }
      rethrow;
    }
  }

  Future<WatchAppraisal> _appraise(String model, List<PhotoInput> photos,
      String extraInfo, bool box, bool papers, bool webSearch) async {
    final prompt = buildPrompt(
      slotLabels: photos.map((p) => p.label).toList(),
      extraInfo: extraInfo,
      box: box,
      papers: papers,
      webSearch: webSearch,
    );
    final body = <String, dynamic>{
      'contents': [
        {
          'role': 'user',
          'parts': [
            for (final p in photos)
              {
                'inline_data': {
                  'mime_type': p.mimeType,
                  'data': base64Encode(p.bytes),
                }
              },
            {'text': prompt},
          ],
        }
      ],
      'generationConfig': {
        'temperature': 0.2,
        if (!webSearch) 'responseMimeType': 'application/json',
      },
      if (webSearch)
        'tools': [
          {'google_search': <String, dynamic>{}}
        ],
    };

    final http.Response res;
    try {
      res = await _http
          .post(Uri.parse('$_base/models/$model:generateContent'),
              headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 120));
    } on TimeoutException {
      throw GeminiException('Il server non ha risposto in tempo. Riprova.');
    }

    if (res.statusCode != 200) {
      final msg = _explain(res);
      final lower = res.body.toLowerCase();
      if (webSearch &&
          res.statusCode == 400 &&
          (lower.contains('tool') ||
              lower.contains('search') ||
              lower.contains('grounding'))) {
        throw GeminiException('[tool] $msg');
      }
      throw GeminiException(msg);
    }

    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
    final parsed = parseGenerateResponse(Map<String, dynamic>.from(data));
    return parsed;
  }

  static String _explain(http.Response res) {
    String detail = '';
    try {
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      detail = (j['error']?['message'] ?? '').toString();
    } catch (_) {}
    switch (res.statusCode) {
      case 400:
        if (detail.toLowerCase().contains('api key')) {
          return 'Chiave API non valida. Controllala nelle Impostazioni.';
        }
        return 'Richiesta non valida: $detail';
      case 401:
      case 403:
        return 'Chiave API non autorizzata. Controllala nelle Impostazioni.';
      case 404:
        return 'Modello non trovato. Nelle Impostazioni tocca "Trova modello".';
      case 429:
        return 'Limite gratuito raggiunto per ora. Aspetta un minuto '
            '(o fino a domani se è il limite giornaliero) e riprova.';
      case 500:
      case 503:
        return 'Il servizio Google è sovraccarico. Riprova tra poco.';
      default:
        return 'Errore ${res.statusCode}: $detail';
    }
  }
}

/// Trasforma la risposta di generateContent in una valutazione.
WatchAppraisal parseGenerateResponse(Map<String, dynamic> data) {
  final candidates = data['candidates'] as List?;
  if (candidates == null || candidates.isEmpty) {
    final reason = data['promptFeedback']?['blockReason'];
    throw GeminiException(reason != null
        ? 'Foto rifiutata dal filtro di sicurezza ($reason).'
        : 'Nessuna risposta dal modello. Riprova.');
  }
  final cand = Map<String, dynamic>.from(candidates.first as Map);
  final parts = (cand['content']?['parts'] as List?) ?? const [];
  final text = parts
      .whereType<Map>()
      .where((p) => p['thought'] != true)
      .map((p) => (p['text'] ?? '').toString())
      .join('\n');
  final json = extractJson(text);
  if (json == null) {
    throw GeminiException(
        'Risposta non leggibile dal modello. Riprova con una foto più nitida.');
  }
  var appraisal = WatchAppraisal.fromJson(json);

  final chunks = (cand['groundingMetadata']?['groundingChunks'] as List?) ??
      const [];
  final sources = <String>[];
  for (final c in chunks) {
    final web = (c is Map) ? c['web'] : null;
    if (web is Map) {
      final title = (web['title'] ?? '').toString();
      final uri = (web['uri'] ?? '').toString();
      if (uri.isNotEmpty) sources.add(title.isEmpty ? uri : '$title|$uri');
    }
  }
  if (sources.isNotEmpty) appraisal = appraisal.withSources(sources);
  return appraisal;
}
