import 'dart:convert';

/// Un segnale sospetto rilevato nelle foto (non è un'autenticazione).
class RedFlag {
  final String severity; // alta | media | bassa
  final String description;

  const RedFlag({required this.severity, required this.description});

  factory RedFlag.fromJson(Object? json) {
    if (json is String) return RedFlag(severity: 'media', description: json);
    final m = (json is Map) ? json : const {};
    return RedFlag(
      severity: _normSeverity(m['severity']),
      description: _str(m['description']) ?? '',
    );
  }

  Map<String, dynamic> toJson() =>
      {'severity': severity, 'description': description};

  static String _normSeverity(Object? v) {
    final s = (v ?? '').toString().toLowerCase();
    if (s.startsWith('a') || s.startsWith('h')) return 'alta';
    if (s.startsWith('b') || s.startsWith('l')) return 'bassa';
    return 'media';
  }
}

/// Un modello alternativo con cui l'orologio potrebbe essere confuso.
class AltMatch {
  final String name;
  final int probability; // 0-100

  const AltMatch({required this.name, required this.probability});

  factory AltMatch.fromJson(Object? json) {
    if (json is String) return AltMatch(name: json, probability: 0);
    final m = (json is Map) ? json : const {};
    return AltMatch(
      name: _str(m['name']) ?? '',
      probability: (parseNumber(m['probability']) ?? 0).round().clamp(0, 100),
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'probability': probability};
}

/// Risultato della valutazione restituito dall'IA.
class WatchAppraisal {
  final bool isWatch;
  final String brand;
  final String model;
  final String? reference;
  final String? caliber;
  final String? era;
  final String? caseMaterial;
  final String? dial;
  final String? condition;
  final int confidence; // 0-100: quanto è sicura l'identificazione
  final double? priceLow;
  final double? priceHigh;
  final double? priceLikely;
  final double? retailNew;
  final String currency;
  final String priceRationale;
  final List<String> comparables;
  final List<RedFlag> redFlags;
  final String authenticityNote;
  final List<String> morePhotos;
  final List<String> sources;
  final List<AltMatch> alternatives;

  const WatchAppraisal({
    required this.isWatch,
    required this.brand,
    required this.model,
    this.reference,
    this.caliber,
    this.era,
    this.caseMaterial,
    this.dial,
    this.condition,
    required this.confidence,
    this.priceLow,
    this.priceHigh,
    this.priceLikely,
    this.retailNew,
    this.currency = 'EUR',
    this.priceRationale = '',
    this.comparables = const [],
    this.redFlags = const [],
    this.authenticityNote = '',
    this.morePhotos = const [],
    this.sources = const [],
    this.alternatives = const [],
  });

  String get title {
    final parts = [brand, model].where((s) => s.trim().isNotEmpty).toList();
    return parts.isEmpty ? 'Orologio non identificato' : parts.join(' ');
  }

  factory WatchAppraisal.fromJson(Map<String, dynamic> j) {
    double? low = parseNumber(j['price_low']);
    double? high = parseNumber(j['price_high']);
    double? likely = parseNumber(j['price_likely']);
    if (low != null && high != null && low > high) {
      final t = low;
      low = high;
      high = t;
    }
    if (likely == null && low != null && high != null) {
      likely = (low + high) / 2;
    }
    return WatchAppraisal(
      isWatch: j['is_watch'] != false,
      brand: _str(j['brand']) ?? '',
      model: _str(j['model']) ?? '',
      reference: _str(j['reference']),
      caliber: _str(j['caliber']),
      era: _str(j['era']),
      caseMaterial: _str(j['case_material']),
      dial: _str(j['dial']),
      condition: _str(j['condition']),
      confidence: (parseNumber(j['confidence']) ?? 0).round().clamp(0, 100),
      priceLow: low,
      priceHigh: high,
      priceLikely: likely,
      retailNew: parseNumber(j['retail_new']),
      currency: (_str(j['currency']) ?? 'EUR').toUpperCase(),
      priceRationale: _str(j['price_rationale']) ?? '',
      comparables: _strList(j['comparables']),
      redFlags: (j['red_flags'] is List)
          ? (j['red_flags'] as List)
              .map(RedFlag.fromJson)
              .where((f) => f.description.isNotEmpty)
              .toList()
          : const [],
      authenticityNote: _str(j['authenticity_note']) ?? '',
      morePhotos: _strList(j['more_photos']),
      sources: _strList(j['sources']),
      alternatives: (j['alternatives'] is List)
          ? (j['alternatives'] as List)
              .map(AltMatch.fromJson)
              .where((a) => a.name.isNotEmpty)
              .toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'is_watch': isWatch,
        'brand': brand,
        'model': model,
        'reference': reference,
        'caliber': caliber,
        'era': era,
        'case_material': caseMaterial,
        'dial': dial,
        'condition': condition,
        'confidence': confidence,
        'price_low': priceLow,
        'price_high': priceHigh,
        'price_likely': priceLikely,
        'retail_new': retailNew,
        'currency': currency,
        'price_rationale': priceRationale,
        'comparables': comparables,
        'red_flags': redFlags.map((f) => f.toJson()).toList(),
        'authenticity_note': authenticityNote,
        'more_photos': morePhotos,
        'sources': sources,
        'alternatives': alternatives.map((a) => a.toJson()).toList(),
      };

  /// Testo pronto per un annuncio di vendita (stile Chrono24/Subito).
  String listingText({bool box = false, bool papers = false}) {
    final b = StringBuffer(title);
    if (reference != null) b.write(' ref. $reference');
    b.writeln();
    void line(String label, String? v) {
      if (v != null && v.trim().isNotEmpty) b.writeln('• $label: $v');
    }

    line('Calibro', caliber);
    line('Periodo', era);
    line('Cassa', caseMaterial);
    line('Quadrante', dial);
    line('Condizioni', condition);
    b.writeln('• Scatola: ${box ? 'sì' : 'no'} – Garanzia/documenti: '
        '${papers ? 'sì' : 'no'}');
    if (priceLikely != null) {
      b.writeln('Prezzo richiesto: ${formatMoney(priceLikely, currency)}');
    }
    return b.toString().trim();
  }

  WatchAppraisal withSources(List<String> extra) {
    final all = {...sources, ...extra}.toList();
    final j = toJson()..['sources'] = all;
    return WatchAppraisal.fromJson(j);
  }
}

/// Una valutazione salvata nella collezione.
class SavedValuation {
  final String id;
  final DateTime date;
  final List<String> photoPaths;
  final WatchAppraisal appraisal;
  final String note;

  /// Valutazioni precedenti dello stesso orologio: (data, prezzo probabile).
  final List<PricePoint> history;
  final List<String> photoLabels;
  final bool box;
  final bool papers;
  final String extraInfo;

  const SavedValuation({
    required this.id,
    required this.date,
    required this.photoPaths,
    required this.appraisal,
    this.note = '',
    this.history = const [],
    this.photoLabels = const [],
    this.box = false,
    this.papers = false,
    this.extraInfo = '',
  });

  /// Tutti i punti di prezzo, incluso quello attuale, in ordine di data.
  List<PricePoint> get timeline => [
        ...history,
        if (appraisal.priceLikely != null)
          PricePoint(date, appraisal.priceLikely!),
      ];

  factory SavedValuation.fromJson(Map<String, dynamic> j) => SavedValuation(
        id: j['id'] as String,
        date: DateTime.tryParse(j['date'] as String? ?? '') ?? DateTime.now(),
        photoPaths: _strList(j['photos']),
        appraisal: WatchAppraisal.fromJson(
            Map<String, dynamic>.from(j['appraisal'] as Map)),
        note: j['note'] as String? ?? '',
        history: (j['history'] is List)
            ? (j['history'] as List)
                .map((e) => PricePoint.fromJson(Map<String, dynamic>.from(e)))
                .toList()
            : const [],
        photoLabels: _strList(j['labels']),
        box: j['box'] == true,
        papers: j['papers'] == true,
        extraInfo: j['extra'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'labels': photoLabels,
        'box': box,
        'papers': papers,
        'extra': extraInfo,
        'id': id,
        'date': date.toIso8601String(),
        'photos': photoPaths,
        'appraisal': appraisal.toJson(),
        'note': note,
        'history': history.map((h) => h.toJson()).toList(),
      };

  static List<SavedValuation> listFromJson(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => SavedValuation.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String listToJson(List<SavedValuation> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());
}

class PricePoint {
  final DateTime date;
  final double value;
  const PricePoint(this.date, this.value);

  factory PricePoint.fromJson(Map<String, dynamic> j) => PricePoint(
      DateTime.tryParse(j['d'] as String? ?? '') ?? DateTime.now(),
      parseNumber(j['v']) ?? 0);

  Map<String, dynamic> toJson() => {'d': date.toIso8601String(), 'v': value};
}

/// Converte numeri anche se arrivano come testo ("12.500 €", "1,2k", "8500").
double? parseNumber(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  var s = v.toString().trim().toLowerCase();
  if (s.isEmpty || s == 'null' || s == 'n/a') return null;
  var mult = 1.0;
  if (s.endsWith('k')) {
    mult = 1000;
    s = s.substring(0, s.length - 1);
  }
  s = s.replaceAll(RegExp(r'[^0-9.,\-]'), '');
  if (s.isEmpty) return null;
  final hasDot = s.contains('.');
  final hasComma = s.contains(',');
  if (hasDot && hasComma) {
    // Il separatore che compare per ultimo è quello decimale.
    if (s.lastIndexOf(',') > s.lastIndexOf('.')) {
      s = s.replaceAll('.', '').replaceAll(',', '.');
    } else {
      s = s.replaceAll(',', '');
    }
  } else if (hasComma) {
    final parts = s.split(',');
    s = (parts.length == 2 && parts[1].length != 3)
        ? s.replaceAll(',', '.')
        : s.replaceAll(',', '');
  } else if (hasDot) {
    final parts = s.split('.');
    if (parts.length > 2 || (parts.length == 2 && parts[1].length == 3)) {
      s = s.replaceAll('.', '');
    }
  }
  final d = double.tryParse(s);
  return d == null ? null : d * mult;
}

/// "12500" -> "12.500 €"
String formatMoney(double? v, [String currency = 'EUR']) {
  if (v == null) return '—';
  final n = v.round().abs();
  final digits = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
    buf.write(digits[i]);
  }
  final sign = v < 0 ? '-' : '';
  final sym = switch (currency) {
    'EUR' => '€',
    'USD' => '\$',
    'GBP' => '£',
    'CHF' => 'CHF',
    _ => currency,
  };
  return '$sign$buf $sym';
}

String? _str(Object? v) {
  if (v == null) return null;
  final s = v.toString().trim();
  if (s.isEmpty || s.toLowerCase() == 'null') return null;
  return s;
}

List<String> _strList(Object? v) {
  if (v is List) {
    return v.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
  }
  if (v is String && v.trim().isNotEmpty) return [v.trim()];
  return const [];
}
