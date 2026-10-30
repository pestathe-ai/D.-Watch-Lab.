import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/appraisal.dart';
import 'gemini_client.dart';
import 'prompt.dart';

/// Servizi IA gratuiti usati come riserva quando Gemini è al limite.
/// Tutti parlano il formato "OpenAI chat completions" con immagini.
enum AltProvider {
  groq('Groq', 'https://api.groq.com/openai/v1',
      'https://console.groq.com/keys'),
  openrouter('OpenRouter', 'https://openrouter.ai/api/v1',
      'https://openrouter.ai/settings/keys'),
  mistral('Mistral', 'https://api.mistral.ai/v1',
      'https://console.mistral.ai/api-keys');

  final String label;
  final String base;
  final String keysUrl;
  const AltProvider(this.label, this.base, this.keysUrl);

  static AltProvider? byName(String? n) {
    for (final p in values) {
      if (p.name == n) return p;
    }
    return null;
  }
}

class AltConfig {
  final AltProvider provider;
  final String key;
  final String model;
  const AltConfig(this.provider, this.key, this.model);
}

/// Sceglie un modello che legge le immagini dall'elenco /models del servizio.
String? pickVisionModel(AltProvider p, List<Map<String, dynamic>> models) {
  final ids = <String>[];
  for (final m in models) {
    final id = (m['id'] ?? '').toString();
    if (id.isEmpty) continue;
    final lower = id.toLowerCase();
    switch (p) {
      case AltProvider.mistral:
        final caps = m['capabilities'];
        final vision = caps is Map && caps['vision'] == true;
        if (!vision) continue;
      case AltProvider.openrouter:
        // Solo modelli gratuiti che accettano immagini.
        if (!lower.endsWith(':free')) continue;
        final arch = m['architecture'];
        final mods = arch is Map ? arch['input_modalities'] : null;
        if (mods is! List || !mods.contains('image')) continue;
      case AltProvider.groq:
        const vis = ['llama-4', 'vision', '-vl', 'scout', 'maverick', 'gemma-3'];
        if (!vis.any(lower.contains)) continue;
        if (lower.contains('guard')) continue;
    }
    ids.add(id);
  }
  if (ids.isEmpty) return null;

  int score(String id) {
    final n = id.toLowerCase();
    var s = 0;
    const prefs = [
      'maverick', 'llama-4', 'qwen', 'mistral-medium', 'pixtral-large',
      'mistral-small', 'gemma-3-27b', 'scout', 'pixtral', 'vision', 'vl',
    ];
    for (var i = 0; i < prefs.length; i++) {
      if (n.contains(prefs[i])) {
        s += (prefs.length - i) * 10;
        break;
      }
    }
    if (n.contains('latest')) s += 3;
    if (n.contains('preview')) s -= 5;
    final b = RegExp(r'(\d+)b').firstMatch(n);
    if (b != null) s += (int.parse(b.group(1)!) ~/ 10).clamp(0, 20);
    return s;
  }

  ids.sort((a, b) => score(b).compareTo(score(a)));
  return ids.first;
}

class AltClient {
  final AltConfig config;
  final http.Client _http;
  AltClient(this.config, {http.Client? client})
      : _http = client ?? http.Client();

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${config.key}',
        'Content-Type': 'application/json',
        if (config.provider == AltProvider.openrouter) ...{
          'HTTP-Referer': 'https://github.com/pestathe-ai',
          'X-Title': 'D. Watch Lab',
        },
      };

  /// Verifica la chiave e restituisce il modello scelto.
  Future<String> resolveModel() async {
    final http.Response res;
    try {
      res = await _http
          .get(Uri.parse('${config.provider.base}/models'), headers: _headers)
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw GeminiException('${config.provider.label} non risponde.', -1);
    } on http.ClientException {
      throw GeminiException('Connessione interrotta.', -1);
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw GeminiException(
          'Chiave ${config.provider.label} non valida.', res.statusCode);
    }
    if (res.statusCode != 200) {
      throw GeminiException(
          '${config.provider.label}: errore ${res.statusCode}.', res.statusCode);
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
    final list = (j['data'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final m = pickVisionModel(config.provider, list);
    if (m == null) {
      throw GeminiException('${config.provider.label}: nessun modello gratuito '
          'che legge le foto disponibile ora.');
    }
    return m;
  }

  Future<WatchAppraisal> appraise({
    required List<PhotoInput> photos,
    String extraInfo = '',
    bool box = false,
    bool papers = false,
  }) {
    final prompt = buildPrompt(
      slotLabels: photos.map((p) => p.label).toList(),
      extraInfo: extraInfo,
      box: box,
      papers: papers,
      webSearch: false,
    );
    return _ask(prompt, photos);
  }

  Future<WatchAppraisal> identify(
          {required List<PhotoInput> photos, String extraInfo = ''}) =>
      _ask(buildIdentifyPrompt(extraInfo: extraInfo), photos.take(2).toList());

  Future<WatchAppraisal> _ask(String prompt, List<PhotoInput> photos) async {
    var model = config.model;
    if (model.isEmpty) model = await resolveModel();
    final mistral = config.provider == AltProvider.mistral;
    final body = {
      'model': model,
      'temperature': 0.2,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            for (final p in photos.take(5))
              {
                'type': 'image_url',
                'image_url': mistral
                    ? 'data:${p.mimeType};base64,${base64Encode(p.bytes)}'
                    : {
                        'url':
                            'data:${p.mimeType};base64,${base64Encode(p.bytes)}'
                      },
              },
          ],
        }
      ],
    };
    final http.Response res;
    try {
      res = await _http
          .post(Uri.parse('${config.provider.base}/chat/completions'),
              headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 90));
    } on TimeoutException {
      throw GeminiException('${config.provider.label} non ha risposto.', -1);
    } on http.ClientException {
      throw GeminiException('Connessione interrotta.', -1);
    }
    if (res.statusCode != 200) {
      String detail = '';
      try {
        detail = (jsonDecode(utf8.decode(res.bodyBytes))['error']?['message'] ??
                '')
            .toString();
      } catch (_) {}
      throw GeminiException(
          res.statusCode == 429
              ? 'Anche ${config.provider.label} è al limite per ora.'
              : '${config.provider.label}: errore ${res.statusCode} $detail'
                  .trim(),
          res.statusCode);
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
    final choices = j['choices'] as List?;
    final content = (choices != null && choices.isNotEmpty)
        ? (choices.first as Map)['message']?['content']
        : null;
    final text = content is String
        ? content
        : (content is List)
            ? content
                .whereType<Map>()
                .map((p) => (p['text'] ?? '').toString())
                .join('\n')
            : '';
    final json = extractJson(text);
    if (json == null) {
      throw GeminiException(
          'Risposta della riserva non leggibile. Riprova.');
    }
    return WatchAppraisal.fromJson(json);
  }
}

/// Prova le alternative in ordine finché una riesce. Si passa alla successiva
/// solo per limiti raggiunti o problemi temporanei; gli altri errori
/// (es. foto non valida) si fermano subito.
Future<T> tryInOrder<T>(
  List<(String, Future<T> Function())> steps, {
  void Function(String)? onStatus,
}) async {
  GeminiException? last;
  for (var i = 0; i < steps.length; i++) {
    final (label, run) = steps[i];
    if (i > 0) onStatus?.call(label);
    try {
      return await run();
    } on GeminiException catch (e) {
      last = e;
      final canSwitch = e.status == 429 || e.transient;
      if (!canSwitch) rethrow;
    }
  }
  throw last ?? GeminiException('Nessuna IA disponibile.');
}
