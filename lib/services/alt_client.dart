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

/// Modelli noti per leggere le foto (provati per primi).
const _knownVision = {
  AltProvider.groq: [
    'qwen/qwen3.8-27b',
    'meta-models/muse-spark-open',
    'meta-llama/llama-4-maverick-17b-128e-instruct',
    'meta-llama/llama-4-scout-17b-16e-instruct',
  ],
};

/// Parole che indicano modelli che NON sono chat (audio, moderazione…).
const _notChat = [
  'whisper', 'tts', 'guard', 'orpheus', 'playai', 'embed', 'transcribe',
  'moderation', 'distil', 'prompt-guard', 'ocr', 'codestral',
];

/// Elenco ordinato dei modelli da provare: prima quelli che sicuramente
/// leggono le immagini, poi quelli che probabilmente le leggono.
List<String> visionCandidates(
    AltProvider p, List<Map<String, dynamic>> models) {
  final sure = <String>[];
  final maybe = <String>[];
  final available = <String>{};
  for (final m in models) {
    final id = (m['id'] ?? '').toString();
    if (id.isEmpty) continue;
    final lower = id.toLowerCase();
    if (_notChat.any(lower.contains)) continue;
    available.add(id);
    switch (p) {
      case AltProvider.mistral:
        final caps = m['capabilities'];
        if (caps is Map && caps['vision'] == true) sure.add(id);
      case AltProvider.openrouter:
        if (!lower.endsWith(':free')) continue;
        final arch = m['architecture'];
        final mods = arch is Map ? arch['input_modalities'] : null;
        if (mods is List && mods.contains('image')) sure.add(id);
      case AltProvider.groq:
        const vis = [
          'vision', '-vl', 'vl-', 'llama-4', 'scout', 'maverick', 'gemma-3',
          'qwen3.', 'muse', 'spark', 'pixtral', 'omni',
        ];
        if (vis.any(lower.contains)) {
          sure.add(id);
        } else {
          maybe.add(id);
        }
    }
  }

  int score(String id) {
    final n = id.toLowerCase();
    var s = 0;
    const prefs = [
      'qwen3.8', 'maverick', 'llama-4', 'qwen', 'mistral-medium',
      'pixtral-large', 'mistral-small', 'gemma-3-27b', 'muse', 'scout',
      'pixtral', 'vision', 'vl',
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

  sure.sort((a, b) => score(b).compareTo(score(a)));
  final known = (_knownVision[p] ?? const <String>[])
      .where(available.contains)
      .toList();
  return {...known, ...sure, ...maybe}.toList();
}

/// Il primo candidato (usato nei test e come ripiego).
String? pickVisionModel(AltProvider p, List<Map<String, dynamic>> models) {
  final c = visionCandidates(p, models);
  return c.isEmpty ? null : c.first;
}

/// Piccola foto JPEG (64x64) usata per verificare che il modello legga le
/// immagini davvero.
const probeJpegBase64 =
    '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';

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
    final candidates = visionCandidates(config.provider, list);
    if (candidates.isEmpty) {
      throw GeminiException('${config.provider.label}: nessun modello '
          'disponibile per questa chiave.');
    }
    // Provo davvero a mandare una foto: tengo il primo che risponde.
    for (final m in candidates.take(8)) {
      if (await probe(m)) return m;
    }
    throw GeminiException('${config.provider.label}: nessun modello gratuito '
        'legge le foto in questo momento. Prova OpenRouter o Mistral.');
  }

  /// true se il modello accetta e capisce una foto.
  Future<bool> probe(String model) async {
    final body = {
      'model': model,
      'max_tokens': 10,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'Cosa vedi? Rispondi con una parola.'},
            {
              'type': 'image_url',
              'image_url': config.provider == AltProvider.mistral
                  ? 'data:image/jpeg;base64,$probeJpegBase64'
                  : {'url': 'data:image/jpeg;base64,$probeJpegBase64'},
            },
          ],
        }
      ],
    };
    try {
      final res = await _http
          .post(Uri.parse('${config.provider.base}/chat/completions'),
              headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 25));
      if (res.statusCode == 429) {
        throw GeminiException(
            '${config.provider.label} è al limite: riprova tra poco.', 429);
      }
      if (res.statusCode == 401 || res.statusCode == 403) {
        // Modello non abilitato per questa chiave (es. anteprime riservate).
        return false;
      }
      return res.statusCode == 200;
    } on TimeoutException {
      return false;
    } on http.ClientException {
      return false;
    }
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

  /// Modello scelto di nuovo se quello salvato smette di leggere foto.
  String? replacedModel;

  Future<WatchAppraisal> _ask(String prompt, List<PhotoInput> photos,
      {bool retried = false}) async {
    var model = replacedModel ?? config.model;
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
            for (final p in photos.take(
                config.provider == AltProvider.groq ? 3 : 5))
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
    if (!retried && (res.statusCode == 400 || res.statusCode == 404)) {
      // Il modello non esiste più o non accetta immagini: ne cerco un altro.
      replacedModel = await resolveModel();
      return _ask(prompt, photos, retried: true);
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
    Object? content;
    if (choices != null && choices.isNotEmpty) {
      final msg = (choices.first as Map)['message'];
      if (msg is Map) content = msg['content'];
    }
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
