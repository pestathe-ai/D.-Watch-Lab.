import 'dart:math' as math;

/// Un annuncio reale trovato su un marketplace.
class Listing {
  final String title;
  final double price;
  final String currency;
  final String condition; // testo come lo dà eBay
  final bool isNew;
  final String url;
  final String? imageUrl;
  final String market; // es. "eBay.it"

  const Listing({
    required this.title,
    required this.price,
    this.currency = 'EUR',
    this.condition = '',
    this.isNew = false,
    required this.url,
    this.imageUrl,
    this.market = 'eBay',
  });

  factory Listing.fromJson(Map<String, dynamic> j) => Listing(
        title: j['t'] as String? ?? '',
        price: (j['p'] as num?)?.toDouble() ?? 0,
        currency: j['c'] as String? ?? 'EUR',
        condition: j['cd'] as String? ?? '',
        isNew: j['n'] == true,
        url: j['u'] as String? ?? '',
        imageUrl: j['i'] as String?,
        market: j['m'] as String? ?? 'eBay',
      );

  Map<String, dynamic> toJson() => {
        't': title,
        'p': price,
        'c': currency,
        'cd': condition,
        'n': isNew,
        'u': url,
        'i': imageUrl,
        'm': market,
      };
}

/// Prezzo di mercato calcolato dagli annunci reali.
class MarketPrice {
  final double likely; // mediana ponderata
  final double low; // 25° percentile
  final double high; // 75° percentile
  final int count; // annunci usati nel calcolo
  final int scanned; // annunci letti in totale
  final double? newMedian;
  final String query;
  final List<Listing> listings; // annunci usati, dal più economico
  final DateTime date;

  const MarketPrice({
    required this.likely,
    required this.low,
    required this.high,
    required this.count,
    required this.scanned,
    this.newMedian,
    required this.query,
    required this.listings,
    required this.date,
  });

  /// Abbastanza annunci per fidarsi del numero.
  bool get reliable => count >= 4;

  String get reliability => count >= 10
      ? 'alta'
      : count >= 6
          ? 'buona'
          : count >= 4
              ? 'discreta'
              : 'bassa';

  factory MarketPrice.fromJson(Map<String, dynamic> j) => MarketPrice(
        likely: (j['likely'] as num).toDouble(),
        low: (j['low'] as num).toDouble(),
        high: (j['high'] as num).toDouble(),
        count: j['count'] as int? ?? 0,
        scanned: j['scanned'] as int? ?? 0,
        newMedian: (j['new'] as num?)?.toDouble(),
        query: j['q'] as String? ?? '',
        listings: (j['items'] as List? ?? [])
            .map((e) => Listing.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        date: DateTime.tryParse(j['date'] as String? ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'likely': likely,
        'low': low,
        'high': high,
        'count': count,
        'scanned': scanned,
        'new': newMedian,
        'q': query,
        'items': listings.map((e) => e.toJson()).toList(),
        'date': date.toIso8601String(),
      };
}

/// Parole che indicano che l'annuncio non è l'orologio completo e funzionante.
const _excludeWords = [
  'cinturino per', 'solo cinturino', 'cinturino ricambio', 'strap for',
  'watch strap', 'watch band', 'band for', 'armband für', 'nur armband',
  'per parti', 'for parts', 'parts only', 'ricambi', 'ricambio', 'spare',
  'ersatzteil', 'non funzionante', 'not working', 'defekt', 'guasto',
  'da riparare', 'scatola vuota', 'solo scatola', 'box only', 'empty box',
  'nur box', 'leere box', 'quadrante per', 'dial for', 'zifferblatt für',
  'vetro per', 'glass for', 'corona per', 'crown for', 'lotto', 'lot of',
  'konvolut', 'replica', 'homage', 'omaggio a', 'custodia per', 'case for',
  'watch box', 'scatola per', 'cassa per', 'movimento per', 'movement for',
  'uhrwerk', 'manuale', 'manual only', 'adesivo', 'sticker', 'fibbia per',
  'buckle for', 'pellicola', 'screen protector', 'batteria per',
];

String normalize(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[àáâä]'), 'a')
    .replaceAll(RegExp(r'[èéêë]'), 'e')
    .replaceAll(RegExp(r'[ìíîï]'), 'i')
    .replaceAll(RegExp(r'[òóôö]'), 'o')
    .replaceAll(RegExp(r'[ùúûü]'), 'u')
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim();

String compact(String s) => normalize(s).replaceAll(' ', '');

const _genericWords = {
  'orologio', 'watch', 'uhr', 'uomo', 'donna', 'men', 'women', 'mens',
  'automatic', 'automatico', 'quartz', 'quarzo', 'acciaio', 'steel', 'the',
  'and', 'con', 'per', 'date', 'data', 'day', 'nero', 'black', 'blu', 'blue',
  'oro', 'gold', 'vintage', 'collection', 'edition',
};

/// Parole del modello utili per riconoscere l'annuncio giusto.
List<String> keyTokens(String model) => normalize(model)
    .split(' ')
    .where((t) => t.length >= 3 && !_genericWords.contains(t))
    .toList();

bool isExcluded(String title) {
  final t = ' ${normalize(title)} ';
  return _excludeWords.any((w) => t.contains(' ${normalize(w)} '));
}

/// Indicazioni dell'IA per cercare e filtrare gli annunci giusti.
class MarketHints {
  /// Ricerca come la scriverebbe un venditore.
  final String query;

  /// Almeno una di queste parole deve comparire nel titolo (es. "vintage",
  /// "anni 40"); usate quando il modello non ha un nome preciso.
  final List<String> must;

  /// Annunci da scartare (es. collezioni moderne della stessa marca).
  final List<String> exclude;

  /// Stima grezza dell'IA: serve a scartare prezzi di un'altra fascia.
  final double? low;
  final double? high;

  const MarketHints({
    this.query = '',
    this.must = const [],
    this.exclude = const [],
    this.low,
    this.high,
  });

  String get cacheKey => normalize(
      '$query | ${must.join(',')} | ${exclude.join(',')}');
}

bool _hasWord(String normalizedTitle, String word) {
  final w = normalize(word);
  if (w.isEmpty) return false;
  return ' $normalizedTitle '.contains(' $w ') ||
      (w.length >= 5 && normalizedTitle.contains(w));
}

/// Tiene solo gli annunci che parlano davvero di quell'orologio.
List<Listing> matchListings(
  List<Listing> all, {
  required String brand,
  required String model,
  String? reference,
  MarketHints? hints,
}) {
  final h = hints ?? const MarketHints();
  final b = normalize(brand);
  final brandTokens = b.split(' ').where((t) => t.length >= 3).toList();
  var pool = all.where((l) {
    if (l.price <= 0) return false;
    if (isExcluded(l.title)) return false;
    final t = normalize(l.title);
    if (brandTokens.isNotEmpty && !brandTokens.any(t.contains)) return false;
    if (h.exclude.any((w) => _hasWord(t, w))) return false;
    // Fascia di prezzo plausibile (larga) secondo la stima dell'IA.
    if (h.low != null && h.low! > 0 && l.price < h.low! / 2.5) return false;
    if (h.high != null && h.high! > 0 && l.price > h.high! * 2.5) return false;
    return true;
  }).toList();

  // 1) Referenza esatta: se almeno 3 annunci la citano, usiamo solo quelli.
  final ref = reference == null ? '' : compact(reference);
  if (ref.length >= 4) {
    final withRef =
        pool.where((l) => compact(l.title).contains(ref)).toList();
    if (withRef.length >= 3) return withRef;
  }

  // 2) Altrimenti le parole chiave del modello (almeno 2/3).
  final tokens = keyTokens(model);
  if (tokens.isEmpty) {
    // Modello senza nome (es. vintage generico): servono le parole indicate
    // dall'IA, altrimenti si finirebbe a fare la media di tutta la marca.
    if (h.must.isEmpty) return const [];
    return pool
        .where((l) => h.must.any((w) => _hasWord(normalize(l.title), w)))
        .toList();
  }
  final need = (tokens.length * 2 / 3).ceil().clamp(1, tokens.length);
  return pool.where((l) {
    final t = normalize(l.title);
    final hits = tokens.where(t.contains).length;
    return hits >= need;
  }).toList();
}

double _quantile(List<double> sorted, double q) {
  if (sorted.isEmpty) return 0;
  final pos = (sorted.length - 1) * q;
  final lo = pos.floor();
  final hi = pos.ceil();
  if (lo == hi) return sorted[lo];
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
}

/// Mediana ponderata.
double weightedMedian(List<double> values, List<double> weights) {
  final idx = List.generate(values.length, (i) => i)
    ..sort((a, b) => values[a].compareTo(values[b]));
  final total = weights.fold<double>(0, (a, b) => a + b);
  var acc = 0.0;
  for (final i in idx) {
    acc += weights[i];
    if (acc >= total / 2) return values[i];
  }
  return values[idx.last];
}

/// Scarta i prezzi fuori scala (scala logaritmica, regola IQR).
List<Listing> removeOutliers(List<Listing> items) {
  if (items.length < 4) return items;
  final logs = items.map((l) => math.log(l.price)).toList()..sort();
  final q1 = _quantile(logs, 0.25);
  final q3 = _quantile(logs, 0.75);
  final iqr = q3 - q1;
  final lo = q1 - 1.5 * iqr;
  final hi = q3 + 1.5 * iqr;
  final median = math.exp(_quantile(logs, 0.5));
  return items.where((l) {
    final v = math.log(l.price);
    if (v < lo || v > hi) return false;
    // Protezione extra: niente sotto 1/3 o sopra 3x la mediana.
    return l.price >= median / 3 && l.price <= median * 3;
  }).toList();
}

/// Calcola il prezzo di mercato ponderato. Restituisce null se non ci sono
/// annunci adatti.
MarketPrice? computeMarketPrice(
  List<Listing> all, {
  required String brand,
  required String model,
  String? reference,
  required String query,
  DateTime? now,
  MarketHints? hints,
}) {
  final matched = matchListings(all,
      brand: brand, model: model, reference: reference, hints: hints);
  final clean = removeOutliers(matched);
  if (clean.isEmpty) return null;

  // Gli usati contano di più (vogliamo il valore del TUO orologio usato);
  // i nuovi pesano meno ma servono quando l'usato scarseggia.
  final used = clean.where((l) => !l.isNew).toList();
  final news = clean.where((l) => l.isNew).toList();
  final values = clean.map((l) => l.price).toList();
  final weights = clean.map((l) => l.isNew ? 0.5 : 1.0).toList();
  final likely = weightedMedian(values, weights);

  final base = (used.length >= 4 ? used : clean).map((l) => l.price).toList()
    ..sort();
  double? newMedian;
  if (news.length >= 2) {
    final n = news.map((l) => l.price).toList()..sort();
    newMedian = _quantile(n, 0.5);
  }
  final sortedListings = [...clean]..sort((a, b) => a.price.compareTo(b.price));
  return MarketPrice(
    likely: likely,
    low: math.min(_quantile(base, 0.25), likely),
    high: math.max(_quantile(base, 0.75), likely),
    count: clean.length,
    scanned: all.length,
    newMedian: newMedian,
    query: query,
    listings: sortedListings.take(30).toList(),
    date: now ?? DateTime.now(),
  );
}

/// Testo di ricerca per i marketplace.
String marketQuery({
  required String brand,
  required String model,
  String? reference,
  bool withReference = true,
}) {
  final parts = <String>[brand.trim()];
  final m = model.trim();
  // Evita di ripetere la marca se il modello la contiene già.
  if (m.isNotEmpty && !normalize(m).startsWith(normalize(brand))) {
    parts.add(m);
  } else if (m.isNotEmpty) {
    parts
      ..clear()
      ..add(m);
  }
  if (withReference && reference != null && reference.trim().isNotEmpty) {
    parts.add(reference.trim());
  }
  return parts.where((p) => p.isNotEmpty).join(' ');
}

/// Link di ricerca su altri mercati.
Uri chrono24Url(String query) => Uri.https('www.chrono24.it',
    '/search/index.htm', {'dosearch': 'true', 'query': query, 'sortorder': '1'});

Uri subitoUrl(String query) => Uri.https(
    'www.subito.it', '/annunci-italia/vendita/usato/', {'q': query});

Uri ebaySearchUrl(String query) =>
    Uri.https('www.ebay.it', '/sch/i.html', {'_nkw': query, '_sacat': '31387'});

Uri catawikiUrl(String query) =>
    Uri.https('www.catawiki.com', '/it/s', {'q': query});
