import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/market.dart';

class EbayException implements Exception {
  final String message;
  EbayException(this.message);
  @override
  String toString() => message;
}

/// Accesso gratuito agli annunci eBay (Browse API, chiave "Application").
class EbayClient {
  static const _tokenUrl = 'https://api.ebay.com/identity/v1/oauth2/token';
  static const _searchUrl =
      'https://api.ebay.com/buy/browse/v1/item_summary/search';
  static const watchCategory = '31387'; // Orologi da polso

  final String clientId;
  final String clientSecret;
  final http.Client _http;

  static String? _token;
  static String? _tokenOwner;
  static DateTime _tokenExpiry = DateTime(2000);
  static Future<String>? _pending;

  EbayClient(this.clientId, this.clientSecret, {http.Client? client})
      : _http = client ?? http.Client();

  static void resetToken() {
    _token = null;
    _tokenOwner = null;
    _pending = null;
  }

  /// Un solo token condiviso anche tra richieste in parallelo.
  Future<String> _getToken() {
    if (_token != null &&
        _tokenOwner == clientId &&
        DateTime.now().isBefore(_tokenExpiry)) {
      return Future.value(_token!);
    }
    return _pending ??= _fetchToken().whenComplete(() => _pending = null);
  }

  Future<String> _fetchToken() async {
    final basic = base64Encode(utf8.encode('$clientId:$clientSecret'));
    final res = await _http
        .post(Uri.parse(_tokenUrl),
            headers: {
              'Authorization': 'Basic $basic',
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: 'grant_type=client_credentials&scope='
                '${Uri.encodeComponent('https://api.ebay.com/oauth/api_scope')}')
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw EbayException(res.statusCode == 401 || res.statusCode == 400
          ? 'Codici eBay non validi. Controlla Client ID e Client Secret '
              '(devono essere quelli di "Production").'
          : 'eBay non risponde (errore ${res.statusCode}).');
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
    _token = j['access_token'] as String;
    _tokenOwner = clientId;
    final secs = (j['expires_in'] as num?)?.toInt() ?? 7200;
    _tokenExpiry = DateTime.now().add(Duration(seconds: secs - 120));
    return _token!;
  }

  /// Verifica i codici (usato nelle Impostazioni).
  Future<void> verify() async {
    resetToken();
    await _getToken();
  }

  /// Cerca annunci a prezzo fisso di orologi su un sito eBay.
  Future<List<Listing>> search(String query,
      {String marketplace = 'EBAY_IT', bool useCategory = true}) async {
    final token = await _getToken();
    final params = <String, String>{
      'q': query,
      'limit': '100',
      'filter': 'buyingOptions:{FIXED_PRICE},priceCurrency:EUR',
    };
    if (useCategory) params['category_ids'] = watchCategory;
    final uri = Uri.parse(_searchUrl).replace(queryParameters: params);
    final res = await _http.get(uri, headers: {
      'Authorization': 'Bearer $token',
      'X-EBAY-C-MARKETPLACE-ID': marketplace,
      'Accept-Language': 'it-IT',
    }).timeout(const Duration(seconds: 15));
    if (res.statusCode == 401) {
      resetToken();
      throw EbayException('Accesso eBay scaduto, riprova.');
    }
    if (res.statusCode != 200) {
      throw EbayException('Ricerca eBay non riuscita (${res.statusCode}).');
    }
    final items = parseSearch(utf8.decode(res.bodyBytes),
        site: marketplace == 'EBAY_DE' ? 'eBay.de' : 'eBay.it');
    // Se la categoria non esiste su quel sito, riprova senza.
    if (items.isEmpty && useCategory) {
      return search(query, marketplace: marketplace, useCategory: false);
    }
    return items;
  }
}

/// Converte la risposta della Browse API in annunci.
List<Listing> parseSearch(String body, {String site = 'eBay'}) {
  final j = jsonDecode(body) as Map;
  final items = (j['itemSummaries'] as List?) ?? const [];
  final out = <Listing>[];
  for (final raw in items) {
    if (raw is! Map) continue;
    final price = raw['price'];
    if (price is! Map) continue;
    final value = double.tryParse('${price['value']}');
    final currency = '${price['currency'] ?? 'EUR'}';
    if (value == null || value <= 0 || currency != 'EUR') continue;
    final condId = int.tryParse('${raw['conditionId'] ?? ''}');
    out.add(Listing(
      title: '${raw['title'] ?? ''}',
      price: value,
      currency: currency,
      condition: '${raw['condition'] ?? ''}',
      isNew: condId != null ? condId < 1500 : false,
      url: '${raw['itemWebUrl'] ?? ''}',
      imageUrl: (raw['image'] is Map) ? raw['image']['imageUrl'] as String? : null,
      market: site,
    ));
  }
  return out;
}

/// Ricerca completa: Italia + Germania in parallelo, poi una ricerca più
/// ampia se gli annunci sono pochi. Restituisce il prezzo calcolato.
Future<MarketPrice?> lookupMarket(
  EbayClient ebay, {
  required String brand,
  required String model,
  String? reference,
}) async {
  if (brand.trim().isEmpty && model.trim().isEmpty) return null;
  final seen = <String>{};
  final all = <Listing>[];

  void addAll(List<Listing> items) {
    for (final l in items) {
      if (seen.add(l.url.isEmpty ? '${l.title}${l.price}' : l.url)) all.add(l);
    }
  }

  Future<void> run(String q) async {
    final results = await Future.wait([
      ebay.search(q, marketplace: 'EBAY_IT'),
      ebay.search(q, marketplace: 'EBAY_DE').catchError((_) => <Listing>[]),
    ]);
    for (final r in results) {
      addAll(r);
    }
  }

  final precise = marketQuery(brand: brand, model: model, reference: reference);
  await run(precise);
  var price = computeMarketPrice(all,
      brand: brand, model: model, reference: reference, query: precise);

  final hasRef = reference != null && reference.trim().isNotEmpty;
  if ((price == null || price.count < 6) && hasRef) {
    final broad = marketQuery(
        brand: brand, model: model, reference: reference, withReference: false);
    if (broad != precise) {
      await run(broad);
      price = computeMarketPrice(all,
          brand: brand, model: model, reference: reference, query: broad);
    }
  }
  return price;
}
