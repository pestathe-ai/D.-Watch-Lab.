import 'dart:convert';

import 'package:d_watch_lab/models/appraisal.dart';
import 'package:d_watch_lab/models/market.dart';
import 'package:d_watch_lab/services/ebay_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Listing l(String title, double price, {bool isNew = false}) =>
    Listing(title: title, price: price, isNew: isNew, url: 'u$title$price');

void main() {
  test('esclude cinturini, ricambi, scatole e lotti', () {
    expect(isExcluded('Cinturino per Citizen Eco-Drive 20mm'), isTrue);
    expect(isExcluded('Citizen orologio PER PARTI non funzionante'), isTrue);
    expect(isExcluded('Scatola vuota Rolex'), isTrue);
    expect(isExcluded('Lotto 5 orologi Citizen'), isTrue);
    expect(isExcluded('Citizen Eco-Drive BM7100 uomo acciaio'), isFalse);
  });

  test('match per referenza quando ci sono abbastanza annunci', () {
    final all = [
      l('Citizen Eco-Drive BM7100-59E uomo', 120),
      l('CITIZEN BM 7100 59E Eco Drive', 110),
      l('Citizen bm7100-59e titanio', 130),
      l('Citizen Eco-Drive BM8180 militare', 90),
      l('Seiko 5 SNK809', 100),
    ];
    final m = matchListings(all,
        brand: 'Citizen', model: 'Eco-Drive', reference: 'BM7100-59E');
    expect(m.length, 3);
  });

  test('senza referenza usa le parole del modello e la marca', () {
    final all = [
      l('Citizen Duke quarzo vintage', 95),
      l('Orologio Citizen Duke anni 80', 120),
      l('Citizen Promaster diver', 200),
      l('Duke orologio generico', 20),
    ];
    final m = matchListings(all, brand: 'Citizen', model: 'Duke');
    expect(m.map((e) => e.price), [95, 120]);
  });

  test('outlier scartati e mediana ponderata', () {
    final items = [
      for (final p in <double>[90, 100, 110, 120, 125, 130, 140]) l('Citizen Duke', p),
      l('Citizen Duke', 5), // fuori scala
      l('Citizen Duke', 2500), // fuori scala
    ];
    final mp = computeMarketPrice(items,
        brand: 'Citizen', model: 'Duke', query: 'Citizen Duke')!;
    expect(mp.count, 7);
    expect(mp.likely, 120);
    expect(mp.low, greaterThanOrEqualTo(90));
    expect(mp.high, lessThanOrEqualTo(140));
    expect(mp.reliable, isTrue);
    expect(mp.listings.first.price, 90);
  });

  test('i nuovi pesano meno degli usati', () {
    final items = [
      for (final p in <double>[100, 105, 110]) l('Citizen Duke', p),
      for (final p in <double>[200, 210, 220]) l('Citizen Duke', p, isNew: true),
    ];
    final mp = computeMarketPrice(items,
        brand: 'Citizen', model: 'Duke', query: 'q')!;
    expect(mp.likely, lessThan(200));
    expect(mp.newMedian, 210);
  });

  test('nessun annuncio adatto -> null', () {
    expect(
        computeMarketPrice([l('Seiko', 100)],
            brand: 'Citizen', model: 'Duke', query: 'q'),
        isNull);
  });

  test('marketQuery non ripete la marca', () {
    expect(marketQuery(brand: 'Citizen', model: 'Citizen Duke'),
        'Citizen Duke');
    expect(marketQuery(brand: 'Rolex', model: 'Submariner', reference: '124060'),
        'Rolex Submariner 124060');
    expect(
        marketQuery(
            brand: 'Rolex',
            model: 'Submariner',
            reference: '124060',
            withReference: false),
        'Rolex Submariner');
  });

  test('link ai mercati', () {
    final u = chrono24Url('Citizen Duke');
    expect(u.host, 'www.chrono24.it');
    expect(u.queryParameters['query'], 'Citizen Duke');
    expect(subitoUrl('a b').queryParameters['q'], 'a b');
  });

  test('parseSearch legge la Browse API', () {
    final body = jsonEncode({
      'itemSummaries': [
        {
          'title': 'Citizen Duke',
          'price': {'value': '99.90', 'currency': 'EUR'},
          'condition': 'Usato',
          'conditionId': '3000',
          'itemWebUrl': 'https://ebay.it/itm/1',
          'image': {'imageUrl': 'https://i.ebayimg.com/1.jpg'}
        },
        {
          'title': 'Citizen nuovo',
          'price': {'value': '150', 'currency': 'EUR'},
          'conditionId': '1000',
          'itemWebUrl': 'https://ebay.it/itm/2'
        },
        {
          'title': 'In dollari',
          'price': {'value': '80', 'currency': 'USD'}
        }
      ]
    });
    final items = parseSearch(body, site: 'eBay.it');
    expect(items.length, 2);
    expect(items[0].price, 99.9);
    expect(items[0].isNew, isFalse);
    expect(items[1].isNew, isTrue);
    expect(items[0].imageUrl, 'https://i.ebayimg.com/1.jpg');
  });

  test('lookupMarket: token, IT+DE, ricerca ampia se pochi annunci', () async {
    final queries = <String>[];
    var tokenCalls = 0;
    EbayClient.resetToken();
    final client = MockClient((req) async {
      if (req.url.path.contains('oauth2')) {
        tokenCalls++;
        expect(req.headers['authorization'], startsWith('Basic '));
        return http.Response(
            jsonEncode({'access_token': 'T', 'expires_in': 7200}), 200);
      }
      expect(req.headers['authorization'], 'Bearer T');
      final q = req.url.queryParameters['q']!;
      queries.add('${req.headers['x-ebay-c-marketplace-id']}:$q');
      final items = q.contains('XYZ1')
          ? <Map<String, dynamic>>[]
          : [
              for (final p in [90, 100, 110, 120, 130, 140])
                {
                  'title': 'Citizen Duke quarzo $p',
                  'price': {'value': '$p', 'currency': 'EUR'},
                  'conditionId': '3000',
                  'itemWebUrl': 'https://ebay/${req.headers['x-ebay-c-marketplace-id']}/$p'
                }
            ];
      return http.Response(jsonEncode({'itemSummaries': items}), 200);
    });
    final mp = await lookupMarket(EbayClient('id', 'sec', client: client),
        brand: 'Citizen', model: 'Duke', reference: 'XYZ1');
    expect(tokenCalls, 1);
    expect(queries, containsAll(['EBAY_IT:Citizen Duke', 'EBAY_DE:Citizen Duke']));
    expect(mp!.count, 12);
    expect(mp.likely, inInclusiveRange(100, 130));
  });

  test('WatchAppraisal usa il prezzo di mercato se affidabile', () {
    final a = WatchAppraisal.fromJson({
      'brand': 'Citizen',
      'model': 'Duke',
      'price_low': 80,
      'price_high': 130,
      'price_likely': 100,
    });
    expect(a.displayLikely, 100);
    final mp = computeMarketPrice([
      for (final p in <double>[90, 100, 110, 120, 130]) l('Citizen Duke', p)
    ], brand: 'Citizen', model: 'Duke', query: 'q');
    final b = a.withMarket(mp);
    expect(b.displayLikely, 110);
    final c = WatchAppraisal.fromJson(
        jsonDecode(jsonEncode(b.toJson())) as Map<String, dynamic>);
    expect(c.market!.count, 5);
    expect(c.displayLikely, 110);
  });

  group('vintage senza nome di modello (es. Jaeger-LeCoultre anni 40)', () {
    final all = [
      l('Jaeger LeCoultre Reverso Classic Large', 5200),
      l('Jaeger-LeCoultre Master Ultra Thin Moon', 6400),
      l('Jaeger LeCoultre Polaris Date', 7100),
      l('Jaeger LeCoultre vintage anni 40 acciaio carica manuale', 1350),
      l('JAEGER LECOULTRE 1940s steel manual wind arabic', 1500),
      l('Vintage Jaeger LeCoultre cal. 450 orologio uomo', 1100),
      l('Jaeger LeCoultre vintage 1945 militare', 1800),
      l('Seiko vintage anni 40', 300),
    ];
    const hints = MarketHints(
      query: 'Jaeger LeCoultre vintage anni 40 carica manuale',
      must: ['vintage', 'anni 40', '1940', '194'],
      exclude: ['Reverso', 'Master', 'Polaris'],
      low: 900,
      high: 2000,
    );

    test('senza indicazioni non fa la media di tutta la marca', () {
      expect(matchListings(all, brand: 'Jaeger-LeCoultre', model: ''),
          isEmpty);
    });

    test('con le indicazioni tiene solo i vintage giusti', () {
      final m = matchListings(all,
          brand: 'Jaeger-LeCoultre', model: '', hints: hints);
      expect(m.map((e) => e.price).toList()..sort(), [1100, 1350, 1500, 1800]);
      final mp = computeMarketPrice(all,
          brand: 'Jaeger-LeCoultre', model: '', query: 'q', hints: hints)!;
      expect(mp.likely, inInclusiveRange(1300, 1550));
    });

    test('la fascia di prezzo scarta i modelli moderni anche senza esclusioni',
        () {
      final m = matchListings(all,
          brand: 'Jaeger-LeCoultre',
          model: '',
          hints: const MarketHints(must: ['vintage', '1940', '194'], low: 900, high: 2000));
      expect(m.every((e) => e.price < 2000 * 2.5), isTrue);
      expect(m.any((e) => e.title.contains('Polaris')), isFalse);
    });

    test('prezzo eBay troppo lontano dalla stima IA: non mi fido', () {
      final a = WatchAppraisal.fromJson({
        'brand': 'Jaeger-LeCoultre',
        'model': '',
        'price_low': 1000,
        'price_high': 1800,
        'price_likely': 1400,
      });
      final wrong = computeMarketPrice([
        for (final p in <double>[4200, 4500, 4600, 4800, 5000])
          l('Jaeger LeCoultre vintage', p)
      ], brand: 'Jaeger-LeCoultre', model: 'x', query: 'q');
      // model 'x' non ha parole chiave valide: uso 'vintage' tramite modello
      final b = a.withMarket(wrong ??
          computeMarketPrice([
            for (final p in <double>[4200, 4500, 4600, 4800, 5000])
              l('Jaeger LeCoultre vintage', p)
          ],
              brand: 'Jaeger-LeCoultre',
              model: '',
              query: 'q',
              hints: const MarketHints(must: ['vintage'])));
      expect(b.market, isNotNull);
      expect(b.marketMismatch, isTrue);
      expect(b.hasMarket, isFalse);
      expect(b.displayLikely, 1400);
    });

    test('le indicazioni sopravvivono al salvataggio', () {
      final a = WatchAppraisal.fromJson({
        'brand': 'JLC',
        'search_query': 'q',
        'must_words': ['vintage'],
        'exclude_words': ['Reverso'],
      });
      final b = WatchAppraisal.fromJson(
          jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>);
      expect(b.hints.must, ['vintage']);
      expect(b.hints.exclude, ['Reverso']);
      expect(b.searchQuery, 'q');
    });
  });
}
