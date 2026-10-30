import 'dart:convert';
import 'dart:typed_data';

import 'package:d_watch_lab/services/alt_client.dart';
import 'package:d_watch_lab/services/gemini_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response jres(Object b, [int code = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(b)), code,
    headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  group('scelta del modello che legge le foto', () {
    test('Groq: preferisce Llama 4, scarta guard e solo testo', () {
      final m = pickVisionModel(AltProvider.groq, [
        {'id': 'llama-3.3-70b-versatile'},
        {'id': 'meta-llama/llama-guard-4-12b'},
        {'id': 'meta-llama/llama-4-scout-17b-16e-instruct'},
        {'id': 'meta-llama/llama-4-maverick-17b-128e-instruct'},
      ]);
      expect(m, 'meta-llama/llama-4-maverick-17b-128e-instruct');
    });

    test('Groq 2026: Qwen 3.8 per primo, audio escluso, testo in coda', () {
      final c = visionCandidates(AltProvider.groq, [
        {'id': 'llama-3.3-70b-versatile'},
        {'id': 'whisper-large-v3'},
        {'id': 'meta-models/muse-spark-open'},
        {'id': 'qwen/qwen3.8-27b'},
      ]);
      expect(c.first, 'qwen/qwen3.8-27b');
      expect(c[1], 'meta-models/muse-spark-open');
      expect(c.last, 'llama-3.3-70b-versatile');
      expect(c.contains('whisper-large-v3'), isFalse);
    });

    test('verifica: prova i modelli con una foto e tiene il primo che va',
        () async {
      final tried = <String>[];
      final c = AltClient(const AltConfig(AltProvider.groq, 'K', ''),
          client: MockClient((req) async {
        if (req.method == 'GET') {
          return jres({
            'data': [
              {'id': 'qwen/qwen3.8-27b'},
              {'id': 'meta-models/muse-spark-open'},
              {'id': 'llama-3.3-70b-versatile'},
            ]
          });
        }
        final b = jsonDecode(req.body) as Map;
        final model = b['model'] as String;
        tried.add(model);
        final img = (b['messages'][0]['content'] as List)[1]['image_url']['url'];
        expect(img, startsWith('data:image/jpeg;base64,/9j/'));
        if (model == 'qwen/qwen3.8-27b') return jres({}, 400);
        if (model == 'meta-models/muse-spark-open') return jres({}, 403);
        return jres({'choices': []});
      }));
      expect(await c.resolveModel(), 'llama-3.3-70b-versatile');
      expect(tried, [
        'qwen/qwen3.8-27b',
        'meta-models/muse-spark-open',
        'llama-3.3-70b-versatile'
      ]);
    });

    test('OpenRouter: solo gratuiti con immagini', () {
      final m = pickVisionModel(AltProvider.openrouter, [
        {
          'id': 'openai/gpt-x',
          'architecture': {'input_modalities': ['text', 'image']}
        },
        {
          'id': 'some/text-model:free',
          'architecture': {'input_modalities': ['text']}
        },
        {
          'id': 'qwen/qwen2.5-vl-72b-instruct:free',
          'architecture': {'input_modalities': ['text', 'image']}
        },
      ]);
      expect(m, 'qwen/qwen2.5-vl-72b-instruct:free');
    });

    test('Mistral: usa il flag vision', () {
      final m = pickVisionModel(AltProvider.mistral, [
        {'id': 'mistral-large-latest', 'capabilities': {'vision': false}},
        {'id': 'pixtral-12b-latest', 'capabilities': {'vision': true}},
        {'id': 'mistral-small-latest', 'capabilities': {'vision': true}},
      ]);
      expect(m, 'mistral-small-latest');
    });
  });

  test('AltClient: formato OpenAI con immagini e lettura del JSON', () async {
    late Map body;
    final c = AltClient(
        const AltConfig(AltProvider.groq, 'K', 'meta-llama/llama-4-scout'),
        client: MockClient((req) async {
      expect(req.url.toString(),
          'https://api.groq.com/openai/v1/chat/completions');
      expect(req.headers['authorization'], 'Bearer K');
      body = jsonDecode(req.body) as Map;
      return jres({
        'choices': [
          {
            'message': {
              'content':
                  '```json\n{"brand":"Citizen","model":"Duke","price_low":90,"price_high":140}\n```'
            }
          }
        ]
      });
    }));
    final a = await c.appraise(photos: [PhotoInput('Q', Uint8List(3))]);
    expect(a.brand, 'Citizen');
    expect(a.priceLikely, 115);
    final content = body['messages'][0]['content'] as List;
    expect(content[1]['image_url']['url'], startsWith('data:image/jpeg;base64,'));
  });

  test('Mistral: immagine come stringa', () async {
    late Map body;
    final c = AltClient(const AltConfig(AltProvider.mistral, 'K', 'm'),
        client: MockClient((req) async {
      body = jsonDecode(req.body) as Map;
      return jres({
        'choices': [
          {
            'message': {'content': '{"brand":"X","model":"Y"}'}
          }
        ]
      });
    }));
    await c.identify(photos: [PhotoInput('Q', Uint8List(3))]);
    final content = body['messages'][0]['content'] as List;
    expect(content[1]['image_url'], isA<String>());
  });

  test('AltClient: 429 diventa errore di limite', () async {
    final c = AltClient(const AltConfig(AltProvider.groq, 'K', 'm'),
        client: MockClient((_) async => jres({}, 429)));
    await expectLater(
        c.appraise(photos: [PhotoInput('Q', Uint8List(1))]),
        throwsA(isA<GeminiException>().having((e) => e.status, 's', 429)));
  });

  group('tryInOrder', () {
    test('limite: passa alla riserva e lo dice', () async {
      final status = <String>[];
      final r = await tryInOrder<String>([
        ('', () async => throw GeminiException('limite', 429)),
        ('Riserva 1…', () async => throw GeminiException('occupato', 503)),
        ('Groq…', () async => 'ok'),
      ], onStatus: status.add);
      expect(r, 'ok');
      expect(status, ['Riserva 1…', 'Groq…']);
    });

    test('errore non di limite: si ferma subito', () async {
      var called = false;
      await expectLater(
          tryInOrder<String>([
            ('', () async => throw GeminiException('chiave non valida', 400)),
            ('x', () async {
              called = true;
              return 'no';
            }),
          ]),
          throwsA(isA<GeminiException>()));
      expect(called, isFalse);
    });

    test('tutte al limite: errore 429', () async {
      await expectLater(
          tryInOrder<String>([
            ('', () async => throw GeminiException('a', 429)),
            ('b', () async => throw GeminiException('b', 429)),
          ]),
          throwsA(isA<GeminiException>().having((e) => e.message, 'm', 'b')));
    });
  });
}
