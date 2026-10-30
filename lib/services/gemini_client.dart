import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' show SocketException, HandshakeException, HttpException;

import 'package:http/http.dart' as http;

import '../models/appraisal.dart';
import 'prompt.dart';

class GeminiException implements Exception {
  final String message;
  final int? status;
  GeminiException(this.message, [this.status]);

  /// Errore temporaneo: server occupato o risposta lenta.
  bool get transient =>
      status == 500 || status == 502 || status == 503 || status == 504 ||
      status == -1;
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

  /// Diventa true se la ricerca web non era disponibile ed è stata saltata.
  bool searchUnavailable = false;

  /// Ragionamento breve = risposta molto più veloce. Se il modello non
  /// accetta l'impostazione, viene tolta automaticamente.
  static bool fastThinking = true;

  GeminiClient(this.apiKey, {http.Client? client})
      : _http = client ?? http.Client();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey,
      };

  /// Elenca i modelli disponibili per la chiave e sceglie il migliore.
  Future<String> resolveModel() async => (await resolveModels()).first;

  /// Tutti i modelli adatti per questa chiave, dal migliore.
  Future<List<String>> resolveModels() async {
    final res = await guardNetwork(() => _http
        .get(Uri.parse('$_base/models?pageSize=200'), headers: _headers)
        .timeout(const Duration(seconds: 20)));
    if (res.statusCode != 200) {
      throw GeminiException(_explain(res), res.statusCode);
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
    final list = (body['models'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final ranked = rankModels(list);
    if (ranked.isEmpty) {
      throw GeminiException(
          'Nessun modello Gemini adatto trovato per questa chiave.');
    }
    return ranked;
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
        searchUnavailable = true;
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
        if (fastThinking) 'thinkingConfig': {'thinkingLevel': 'low'},
      },
      if (webSearch)
        'tools': [
          {'google_search': <String, dynamic>{}}
        ],
    };

    final res = await guardNetwork(() => _http
        .post(Uri.parse('$_base/models/$model:generateContent'),
            headers: _headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 100)));

    if (res.statusCode != 200) {
      final msg = _explain(res);
      final lower = res.body.toLowerCase();
      if (fastThinking && res.statusCode == 400 && lower.contains('thinking')) {
        fastThinking = false;
        return _appraise(model, photos, extraInfo, box, papers, webSearch);
      }
      // Sul piano gratuito la ricerca Google non è inclusa: Google risponde
      // 429 (quota zero) o 400. In entrambi i casi riprovo senza ricerca.
      if (webSearch && res.statusCode == 429) {
        throw GeminiException('[tool] $msg', 429);
      }
      if (webSearch &&
          res.statusCode == 400 &&
          (lower.contains('tool') ||
              lower.contains('search') ||
              lower.contains('grounding'))) {
        throw GeminiException('[tool] $msg', 400);
      }
      throw GeminiException(msg, res.statusCode);
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
            '(o fino a domani se è il limite giornaliero) e riprova.'
            '${detail.isEmpty ? '' : '\n\nDettaglio Google: ${detail.split('\n').first}'}';
      case 500:
      case 502:
      case 503:
      case 504:
        return 'I server di Google sono molto occupati in questo momento. '
            'Ho già riprovato con altri modelli: riprova tra un minuto.';
      default:
        return 'Errore ${res.statusCode}: $detail';
    }
  }
}

/// Trasforma i problemi di rete (connessione interrotta, cambio Wi-Fi/dati,
/// timeout) in un errore temporaneo che l'app riprova da sola.
Future<http.Response> guardNetwork(Future<http.Response> Function() call) async {
  try {
    return await call();
  } on TimeoutException {
    throw GeminiException(
        'Google non ha risposto in tempo. Controlla la connessione e riprova.',
        -2);
  } on SocketException {
    throw GeminiException(
        'Connessione interrotta. Controlla internet e riprova.', -1);
  } on HandshakeException {
    throw GeminiException(
        'Connessione interrotta. Controlla internet e riprova.', -1);
  } on HttpException {
    throw GeminiException(
        'Connessione interrotta. Controlla internet e riprova.', -1);
  } on http.ClientException {
    throw GeminiException(
        'Connessione interrotta (rete cambiata o app in background). '
        'Riprova tenendo l\'app aperta.',
        -1);
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
