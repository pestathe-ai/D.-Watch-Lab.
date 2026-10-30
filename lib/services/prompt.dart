import 'dart:convert';

/// Tipi di foto guidate: più angolazioni = stima più precisa.
class PhotoSlot {
  final String key;
  final String label;
  final String hint;
  final bool required;
  const PhotoSlot(this.key, this.label, this.hint, {this.required = false});
}

const photoSlots = <PhotoSlot>[
  PhotoSlot('dial', 'Quadrante', 'Frontale, dritto, senza riflessi',
      required: true),
  PhotoSlot('caseback', 'Fondello', 'Incisioni, numeri, eventuale vetro'),
  PhotoSlot('side', 'Lato e corona', 'Corona, pulsanti, spessore cassa'),
  PhotoSlot('clasp', 'Fibbia / bracciale', 'Logo e codici sulla chiusura'),
  PhotoSlot('lugs', 'Tra le anse', 'Numero di referenza e seriale'),
  PhotoSlot('papers', 'Scatola / garanzia', 'Documenti e scatola originali'),
];

String buildPrompt({
  required List<String> slotLabels,
  String extraInfo = '',
  bool box = false,
  bool papers = false,
  bool webSearch = true,
}) {
  final photos = <String>[
    for (var i = 0; i < slotLabels.length; i++)
      'Foto ${i + 1}: ${slotLabels[i]}',
  ].join('\n');
  final extra = extraInfo.trim().isEmpty ? 'nessuna' : extraInfo.trim();
  final search = webSearch
      ? 'Usa la ricerca Google per verificare la referenza e trovare prezzi '
          'REALI recenti di esemplari usati (Chrono24, aste, rivenditori, '
          'annunci venduti). Basa la forbice su quei prezzi.'
      : 'Non hai accesso al web: stima i prezzi dalle tue conoscenze del '
          'mercato e abbassa la confidenza di conseguenza.';

  return '''
Sei un perito orologiaio esperto del mercato dell'usato in Europa.
Analizza le foto di un orologio, identificalo con precisione e stimane il
valore di mercato ATTUALE come usato, cioè il prezzo tipico degli annunci
online (eBay, Chrono24, Subito) per lo stesso modello in condizioni simili.
Non sottostimare: non dare il prezzo di realizzo in svendita.

Foto fornite:
$photos

Informazioni del proprietario: $extra
Scatola originale: ${box ? 'sì' : 'no'} – Garanzia/documenti: ${papers ? 'sì' : 'no'}

Metodo:
1. Leggi con attenzione ogni scritta: marca, nome modello, testi sul
   quadrante, incisioni sul fondello, numeri tra le anse, codici sulla fibbia.
2. Identifica la referenza esatta. Se non puoi leggerla, deducila da lunetta,
   lancette, indici, data, dimensioni, bracciale, e dillo.
3. Elenca fino a 3 modelli alternativi plausibili con probabilità, così
   l'utente vede i possibili errori di identificazione.
4. $search
5. Considera condizioni visibili, scatola e documenti (full set vale di più).
6. Cerca segnali di possibile falso o parti non originali (font del
   quadrante, allineamento, data, finiture, incisioni, logo della corona).
   NON dichiarare mai l'orologio autentico: puoi solo segnalare dubbi.
7. Se mancano angolazioni utili, indica quali foto aggiungere.
8. Sii onesto: se la foto è scarsa o il modello è incerto, abbassa la
   confidenza e allarga la forbice. Non inventare referenze.
Attenzione ai vintage senza nome di modello: il valore dipende da epoca,
calibro, materiale e condizioni del quadrante, non dai modelli moderni della
stessa marca. Un quadrante rovinato o restaurato abbassa molto il prezzo.
Se la foto non mostra un orologio, metti is_watch a false.

Rispondi SOLO con un oggetto JSON valido, testi in italiano, numeri senza
simboli, prezzi in EUR, con questi campi:
{
  "is_watch": true,
  "brand": "",
  "model": "",
  "reference": "o null",
  "caliber": "o null",
  "era": "anno o periodo stimato",
  "case_material": "",
  "dial": "colore e tipo di quadrante",
  "condition": "giudizio sulle condizioni visibili",
  "confidence": 0,
  "alternatives": [{"name": "", "probability": 0}],
  "price_low": 0,
  "price_high": 0,
  "price_likely": 0,
  "retail_new": "prezzo di listino del nuovo o null",
  "currency": "EUR",
  "price_rationale": "come hai ricavato la forbice, 2-3 frasi",
  "comparables": ["esempi di prezzi reali trovati, con fonte"],
  "red_flags": [{"severity": "alta|media|bassa", "description": ""}],
  "authenticity_note": "giudizio prudente, 1-2 frasi",
  "more_photos": ["foto da aggiungere per migliorare la stima"],
  "search_query": "come un venditore titolerebbe l'annuncio su eBay",
  "must_words": ["parole tipiche dei titoli di annunci dello stesso tipo"],
  "exclude_words": ["modelli della stessa marca da non confondere"]
}
confidence = quanto sei sicuro dell'identificazione (0-100).
'''
      .trim();
}

/// Estrae il primo oggetto JSON da una risposta (anche se dentro ```json).
Map<String, dynamic>? extractJson(String text) {
  var t = text.trim();
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(t);
  if (fence != null) t = fence.group(1)!.trim();
  final start = t.indexOf('{');
  if (start < 0) return null;
  var depth = 0;
  var inStr = false;
  var esc = false;
  for (var i = start; i < t.length; i++) {
    final c = t[i];
    if (inStr) {
      if (esc) {
        esc = false;
      } else if (c == '\\') {
        esc = true;
      } else if (c == '"') {
        inStr = false;
      }
      continue;
    }
    if (c == '"') {
      inStr = true;
    } else if (c == '{') {
      depth++;
    } else if (c == '}') {
      depth--;
      if (depth == 0) {
        final candidate = t.substring(start, i + 1);
        try {
          final v = jsonDecode(candidate);
          if (v is Map) return Map<String, dynamic>.from(v);
        } catch (_) {
          // Prova a ripulire virgole finali.
          final cleaned = candidate.replaceAllMapped(
              RegExp(r',\s*([}\]])'), (m) => m.group(1)!);
          try {
            final v = jsonDecode(cleaned);
            if (v is Map) return Map<String, dynamic>.from(v);
          } catch (_) {}
        }
        return null;
      }
    }
  }
  return null;
}

/// Sceglie il miglior modello Gemini "Flash" disponibile per la chiave.
/// [models] è l'elenco restituito da GET /v1beta/models.
String? pickBestModel(List<Map<String, dynamic>> models) {
  final r = rankModels(models);
  return r.isEmpty ? null : r.first;
}

/// Tutti i modelli Flash adatti, dal migliore al peggiore.
List<String> rankModels(List<Map<String, dynamic>> models) {
  final candidates = <String>[];
  for (final m in models) {
    final name = (m['name'] ?? '').toString().replaceFirst('models/', '');
    final methods = (m['supportedGenerationMethods'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const [];
    if (!methods.contains('generateContent')) continue;
    if (!name.startsWith('gemini')) continue;
    if (!name.contains('flash')) continue;
    const bad = ['image', 'tts', 'audio', 'live', 'embedding', 'thinking-exp',
        'robotics', 'omni', 'computer'];
    if (bad.any(name.contains)) continue;
    candidates.add(name);
  }
  if (candidates.isEmpty) return const [];

  int score(String n) {
    var s = 0;
    final v = RegExp(r'gemini-(\d+(?:\.\d+)?)').firstMatch(n);
    if (v != null) s += (double.parse(v.group(1)!) * 100).round();
    if (n.contains('lite')) s -= 30; // meno preciso
    if (n.contains('preview') || n.contains('exp')) s -= 20;
    if (RegExp(r'-\d{3}$').hasMatch(n)) s -= 1; // versioni fissate
    if (n == 'gemini-flash-latest') s += 100000;
    if (n.contains('latest')) s += 5;
    return s;
  }

  candidates.sort((a, b) => score(b).compareTo(score(a)));
  return candidates.toSet().toList();
}

/// Richiesta lampo: solo identificazione, risposta minima.
String buildIdentifyPrompt({String extraInfo = ''}) {
  final extra = extraInfo.trim().isEmpty ? '' : '\nInfo del proprietario: ${extraInfo.trim()}';
  return '''
Sei un esperto di orologi e del mercato dell'usato. Identifica l'orologio nella
foto leggendo con cura le scritte (marca, modello) e osservando stile, epoca,
cassa, quadrante e lancette.$extra
Rispondi SOLO con JSON, senza altro testo:
$_identifyFields'''
      .trim();
}

const _identifyFields = '''
{"is_watch": true, "brand": "", "model": "", "reference": null,
 "era": "", "confidence": 0,
 "search_query": "", "must_words": [], "exclude_words": [],
 "price_low": 0, "price_high": 0}
- model: nome commerciale (es. "Submariner Date", "Tank Must"), senza la
  marca. Se è un vintage senza nome di modello lascia "".
- reference: codice solo se leggibile o certo, altrimenti null.
- era: anno o decennio stimato (es. "anni 40").
- search_query: come un venditore titolerebbe l'annuncio su eBay per QUESTO
  tipo di orologio (es. "Jaeger LeCoultre vintage anni 40 carica manuale").
- must_words: 2-5 parole di cui almeno una compare nel titolo di un annuncio
  dello stesso tipo (per un vintage: "vintage", "anni 40", "1940", "194").
- exclude_words: modelli/collezioni della stessa marca molto diversi per
  epoca o fascia di prezzo da escludere (es. "Reverso", "Master", "Polaris").
- price_low/price_high: forbice grezza in EUR del valore come usato in
  queste condizioni (serve a scartare annunci fuori fascia).
Se non è un orologio, is_watch false.''';

/// Il modello più rapido disponibile (Flash-Lite più recente, altrimenti il
/// primo della classifica).
String? pickFastModel(List<Map<String, dynamic>> models) {
  final ranked = rankModels(models);
  final lite = ranked.where((n) => n.contains('lite')).toList();
  if (lite.isNotEmpty) return lite.first;
  return ranked.isEmpty ? null : ranked.first;
}
