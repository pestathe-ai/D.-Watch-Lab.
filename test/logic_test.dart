import 'dart:convert';
import 'dart:typed_data';

import 'package:d_watch_lab/models/appraisal.dart';
import 'package:d_watch_lab/screens/collection_screen.dart';
import 'package:d_watch_lab/services/appraisal_runner.dart';
import 'package:d_watch_lab/services/gemini_client.dart';
import 'package:d_watch_lab/services/prompt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response jsonRes(Object body, int code) => http.Response.bytes(
    utf8.encode(jsonEncode(body)), code,
    headers: {'content-type': 'application/json; charset=utf-8'});

const sampleJson = '''
{
  "is_watch": true,
  "brand": "Rolex",
  "model": "Submariner Date",
  "reference": "126610LN",
  "caliber": "3235",
  "era": "2021",
  "case_material": "Acciaio Oystersteel",
  "dial": "Nero",
  "condition": "Ottime",
  "confidence": "88",
  "alternatives": [{"name": "Submariner 124060", "probability": 10}],
  "price_low": "11.800",
  "price_high": 13500,
  "price_likely": null,
  "retail_new": "10.900 €",
  "currency": "eur",
  "price_rationale": "Prezzi Chrono24 recenti.",
  "comparables": ["Chrono24: 12.400 € full set"],
  "red_flags": [{"severity": "High", "description": "Lunetta da verificare"}, "Font della data"],
  "authenticity_note": "Nessun problema evidente.",
  "more_photos": ["Fondello"]
}''';

void main() {
  group('parseNumber', () {
    test('formati italiani e inglesi', () {
      expect(parseNumber('12.500'), 12500);
      expect(parseNumber('12.500,50 €'), 12500.5);
      expect(parseNumber('12,500.50'), 12500.5);
      expect(parseNumber('1,5'), 1.5);
      expect(parseNumber('8500'), 8500);
      expect(parseNumber('1.2k'), 1200);
      expect(parseNumber(9000), 9000);
      expect(parseNumber('null'), isNull);
      expect(parseNumber(''), isNull);
      expect(parseNumber('1.234.567'), 1234567);
    });
  });

  test('formatMoney', () {
    expect(formatMoney(12500), '12.500 €');
    expect(formatMoney(999), '999 €');
    expect(formatMoney(1234567.4), '1.234.567 €');
    expect(formatMoney(null), '—');
    expect(formatMoney(-1500), '-1.500 €');
  });

  test('WatchAppraisal.fromJson normalizza i campi', () {
    final a = WatchAppraisal.fromJson(jsonDecode(sampleJson));
    expect(a.title, 'Rolex Submariner Date');
    expect(a.confidence, 88);
    expect(a.priceLow, 11800);
    expect(a.priceHigh, 13500);
    expect(a.priceLikely, 12650); // media se manca
    expect(a.retailNew, 10900);
    expect(a.currency, 'EUR');
    expect(a.redFlags.length, 2);
    expect(a.redFlags.first.severity, 'alta');
    expect(a.redFlags[1].severity, 'media');
    expect(a.alternatives.single.probability, 10);
    // andata e ritorno
    final b = WatchAppraisal.fromJson(
        jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>);
    expect(b.toJson(), a.toJson());
  });

  test('forbice invertita viene corretta', () {
    final a = WatchAppraisal.fromJson(
        {'brand': 'X', 'price_low': 500, 'price_high': 300});
    expect(a.priceLow, 300);
    expect(a.priceHigh, 500);
  });

  test('extractJson gestisce code fence, testo extra e virgole finali', () {
    expect(extractJson('Ecco:\n```json\n{"a": 1}\n```')!['a'], 1);
    expect(extractJson('blah {"a": {"b": "}"}} fine')!['a']['b'], '}');
    expect(extractJson('{"a": [1,2,],}')!['a'], [1, 2]);
    expect(extractJson('niente'), isNull);
  });

  test('pickBestModel sceglie il Flash più recente e stabile', () {
    List<Map<String, dynamic>> m(List<String> names) => [
          for (final n in names)
            {
              'name': 'models/$n',
              'supportedGenerationMethods': ['generateContent']
            }
        ];
    expect(
        pickBestModel(m([
          'gemini-2.5-flash',
          'gemini-3.6-flash',
          'gemini-3.8-flash',
          'gemini-3.5-flash-lite',
          'gemini-3.1-flash-image-preview',
          'gemini-2.5-pro',
        ])),
        'gemini-3.8-flash');
    expect(pickBestModel(m(['gemini-flash-latest', 'gemini-9-flash'])),
        'gemini-flash-latest');
    expect(pickBestModel(m(['gemini-2.5-pro', 'text-embedding-004'])), isNull);
    expect(
        pickBestModel([
          {
            'name': 'models/gemini-3.8-flash',
            'supportedGenerationMethods': ['embedContent']
          }
        ]),
        isNull);
  });

  test('buildPrompt contiene foto e corredo', () {
    final p = buildPrompt(
        slotLabels: ['Quadrante', 'Fondello'], box: true, papers: false);
    expect(p, contains('Foto 2: Fondello'));
    expect(p, contains('Scatola originale: sì'));
    expect(p, contains('"price_low"'));
  });

  test('listingText', () {
    final a = WatchAppraisal.fromJson(jsonDecode(sampleJson));
    final txt = a.listingText(box: true, papers: true);
    expect(txt, startsWith('Rolex Submariner Date ref. 126610LN'));
    expect(txt, contains('Prezzo richiesto: 12.650 €'));
  });

  test('SavedValuation timeline e totali collezione', () {
    final a = WatchAppraisal.fromJson(jsonDecode(sampleJson));
    final v = SavedValuation(
      id: '1',
      date: DateTime(2026, 10, 1),
      photoPaths: const ['a.jpg'],
      appraisal: a,
      history: [PricePoint(DateTime(2026, 1, 1), 11000)],
      box: true,
    );
    final round = SavedValuation.listFromJson(SavedValuation.listToJson([v]));
    expect(round.single.timeline.map((p) => p.value), [11000, 12650]);
    expect(round.single.box, isTrue);
    final tot = collectionTotals([v, v]);
    expect(tot.likely, 25300);
    expect(tot.low, 23600);
    expect(SavedValuation.listFromJson('rotto'), isEmpty);
  });

  group('GeminiClient (server simulato)', () {
    Map<String, dynamic> okBody() => {
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'ragionamento', 'thought': true},
                  {'text': '```json\n$sampleJson\n```'}
                ]
              },
              'groundingMetadata': {
                'groundingChunks': [
                  {
                    'web': {'title': 'chrono24.it', 'uri': 'https://x.y/1'}
                  }
                ]
              }
            }
          ]
        };

    test('invia foto e ricerca web, legge risultato e fonti', () async {
      late Map<String, dynamic> sent;
      final client = MockClient((req) async {
        expect(req.headers['x-goog-api-key'], 'KEY');
        expect(req.url.path, endsWith('/models/gemini-x-flash:generateContent'));
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return jsonRes(okBody(), 200);
      });
      final g = GeminiClient('KEY', client: client);
      final a = await g.appraise(
          model: 'gemini-x-flash',
          photos: [PhotoInput('Quadrante', Uint8List.fromList([1, 2, 3]))]);
      expect(a.reference, '126610LN');
      expect(a.sources, ['chrono24.it|https://x.y/1']);
      final parts = sent['contents'][0]['parts'] as List;
      expect(parts.first['inline_data']['data'], base64Encode([1, 2, 3]));
      expect(sent['tools'], isNotNull);
    });

    test('se la ricerca web non è supportata riprova senza', () async {
      var calls = 0;
      final client = MockClient((req) async {
        calls++;
        final body = jsonDecode(req.body) as Map;
        if (body.containsKey('tools')) {
          return jsonRes({
            'error': {'message': 'Tool google_search is not supported'}
          }, 400);
        }
        expect(body['generationConfig']['responseMimeType'],
            'application/json');
        return jsonRes(okBody(), 200);
      });
      final a = await GeminiClient('K', client: client).appraise(
          model: 'm', photos: [PhotoInput('Q', Uint8List(1))]);
      expect(calls, 2);
      expect(a.brand, 'Rolex');
    });

    test('429 con ricerca web: riprova senza ricerca', () async {
      var calls = 0;
      final client = MockClient((req) async {
        calls++;
        final body = jsonDecode(req.body) as Map;
        if (body.containsKey('tools')) return jsonRes({}, 429);
        return jsonRes(okBody(), 200);
      });
      final g = GeminiClient('K', client: client);
      final a = await g.appraise(
          model: 'm', photos: [PhotoInput('Q', Uint8List(1))]);
      expect(calls, 2);
      expect(g.searchUnavailable, isTrue);
      expect(a.brand, 'Rolex');
    });

    test('connessione interrotta = errore temporaneo', () async {
      final client = MockClient((_) async =>
          throw http.ClientException('Software caused connection abort'));
      await expectLater(
          GeminiClient('K', client: client).appraise(
              model: 'm',
              photos: [PhotoInput('Q', Uint8List(1))],
              webSearch: false),
          throwsA(isA<GeminiException>()
              .having((e) => e.transient, 'transient', isTrue)
              .having((e) => e.message, 'msg', contains('Connessione'))));
    });

    test('errori tradotti in italiano', () async {
      final client = MockClient((_) async => http.Response('{}', 429));
      expect(
          () => GeminiClient('K', client: client)
              .appraise(
                  model: 'm',
                  photos: [PhotoInput('Q', Uint8List(1))],
                  webSearch: false),
          throwsA(isA<GeminiException>().having(
              (e) => e.message, 'msg', contains('Limite gratuito'))));
    });

    test('resolveModel usa l\'elenco dei modelli', () async {
      final client = MockClient((req) async => jsonRes({
            'models': [
              {
                'name': 'models/gemini-3.6-flash',
                'supportedGenerationMethods': ['generateContent']
              }
            ]
          }, 200));
      expect(await GeminiClient('K', client: client).resolveModel(),
          'gemini-3.6-flash');
    });
  });

  group('tentativi e cambio modello', () {
    GeminiClient lister(List<String> names) => GeminiClient('K',
        client: MockClient((req) async => jsonRes({
              'models': [
                for (final n in names)
                  {
                    'name': 'models/$n',
                    'supportedGenerationMethods': ['generateContent']
                  }
              ]
            }, 200)));

    test('503 ripetuto: riprova e poi passa al modello successivo', () async {
      final calls = <String>[];
      final statuses = <String>[];
      String? worked;
      final r = await appraiseWithFallback<String>(
        client: lister(['gemini-3.8-flash', 'gemini-3.6-flash']),
        savedModel: 'gemini-3.8-flash',
        run: (m) async {
          calls.add(m);
          if (m == 'gemini-3.8-flash') throw GeminiException('busy', 503);
          return 'ok:$m';
        },
        onModelWorked: (m) async => worked = m,
        wait: (_) => Duration.zero,
        onStatus: statuses.add,
      );
      expect(r, 'ok:gemini-3.6-flash');
      expect(calls, ['gemini-3.8-flash', 'gemini-3.8-flash', 'gemini-3.8-flash', 'gemini-3.6-flash']);
      expect(worked, 'gemini-3.6-flash');
      expect(statuses, contains('Provo un altro modello IA…'));
    });

    test('rete caduta una volta: riprova e riesce', () async {
      var n = 0;
      final statuses = <String>[];
      final r = await appraiseWithFallback<String>(
        client: lister(['gemini-flash-latest']),
        savedModel: 'gemini-flash-latest',
        run: (m) async {
          n++;
          if (n == 1) throw GeminiException('rete', -1);
          return 'ok';
        },
        onModelWorked: (_) async {},
        wait: (_) => Duration.zero,
        onStatus: statuses.add,
      );
      expect(r, 'ok');
      expect(n, 2);
      expect(statuses, ['Connessione interrotta, riprovo…']);
    });

    test('chiave non valida: nessun cambio modello', () async {
      var n = 0;
      await expectLater(
        appraiseWithFallback<String>(
          client: lister(['a-flash']),
          savedModel: 'gemini-x-flash',
          run: (m) async {
            n++;
            throw GeminiException('Chiave API non valida', 400);
          },
          onModelWorked: (_) async {},
          wait: (_) => Duration.zero,
        ),
        throwsA(isA<GeminiException>()),
      );
      expect(n, 1);
    });

    test('nessun modello salvato: usa il migliore della lista', () async {
      final r = await appraiseWithFallback<String>(
        client: lister(['gemini-2.5-flash', 'gemini-3.6-flash']),
        savedModel: '',
        run: (m) async => m,
        onModelWorked: (_) async {},
        wait: (_) => Duration.zero,
      );
      expect(r, 'gemini-3.6-flash');
    });

    test('tutti occupati: errore chiaro dopo massimo 3 modelli', () async {
      final calls = <String>[];
      await expectLater(
        appraiseWithFallback<String>(
          client: lister(['gemini-3.8-flash', 'gemini-3.6-flash',
              'gemini-3.5-flash-lite', 'gemini-2.5-flash']),
          savedModel: '',
          run: (m) async {
            calls.add(m);
            throw GeminiException('busy', 503);
          },
          onModelWorked: (_) async {},
          wait: (_) => Duration.zero,
        ),
        throwsA(isA<GeminiException>()),
      );
      expect(calls.toSet().length, 3);
    });
  });
}
