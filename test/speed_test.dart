import 'dart:convert';
import 'dart:typed_data';

import 'package:d_watch_lab/services/gemini_client.dart';
import 'package:d_watch_lab/services/prompt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

List<Map<String, dynamic>> models(List<String> names) => [
      for (final n in names)
        {
          'name': 'models/$n',
          'supportedGenerationMethods': ['generateContent']
        }
    ];

void main() {
  test('pickFastModel preferisce il Flash-Lite più recente', () {
    expect(
        pickFastModel(models([
          'gemini-flash-latest',
          'gemini-3.8-flash',
          'gemini-3.5-flash-lite',
          'gemini-3.1-flash-lite',
          'gemini-3.1-flash-lite-preview',
        ])),
        'gemini-3.5-flash-lite');
    expect(pickFastModel(models(['gemini-3.8-flash'])), 'gemini-3.8-flash');
    expect(pickFastModel(models(['gemini-2.5-pro'])), isNull);
  });

  test('prompt di identificazione è corto e chiede solo JSON', () {
    final p = buildIdentifyPrompt(extraInfo: 'anno 1985');
    expect(p, contains('"brand"'));
    expect(p, contains('anno 1985'));
    expect(p.length, lessThan(900));
  });

  test('identify: JSON forzato, max 2 foto, legge marca e modello', () async {
    late Map body;
    final client = MockClient((req) async {
      body = jsonDecode(req.body) as Map;
      return http.Response.bytes(
          utf8.encode(jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'text':
                          '{"is_watch":true,"brand":"Cartier","model":"Tank Must","reference":"WSTA0041","confidence":82}'
                    }
                  ]
                }
              }
            ]
          })),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    final r = await GeminiClient('K', client: client).identify(
        model: 'm',
        photos: [
          for (var i = 0; i < 4; i++) PhotoInput('Q$i', Uint8List(1))
        ]);
    expect(r.brand, 'Cartier');
    expect(r.model, 'Tank Must');
    expect(r.reference, 'WSTA0041');
    expect(body['generationConfig']['responseMimeType'], 'application/json');
    expect(body.containsKey('tools'), isFalse);
    final parts = body['contents'][0]['parts'] as List;
    expect(parts.where((p) => (p as Map).containsKey('inline_data')).length, 2);
  });

  test('connessione interrotta = errore temporaneo (si riprova)', () async {
    final client = MockClient((_) async =>
        throw http.ClientException('Software caused connection abort'));
    await expectLater(
        GeminiClient('K', client: client).identify(
            model: 'm', photos: [PhotoInput('Q', Uint8List(1))]),
        throwsA(isA<GeminiException>()
            .having((e) => e.transient, 'transient', isTrue)));
  });
}
