import 'dart:async';
import 'dart:io';

import '../models/appraisal.dart';
import 'ebay_client.dart';
import 'gemini_client.dart';
import 'storage.dart';

class MissingKeyException implements Exception {}

/// Esegue una valutazione completa con tentativi automatici:
/// se un modello è occupato o al limite, riprova e poi passa al successivo.
/// [onStatus] riceve messaggi brevi da mostrare all'utente.
Future<WatchAppraisal> runAppraisal({
  required Storage storage,
  required List<File> photos,
  required List<String> labels,
  String extraInfo = '',
  bool box = false,
  bool papers = false,
  void Function(String)? onStatus,
  GeminiClient? clientOverride,
  Duration Function(int attempt)? backoff,
}) async {
  final settings = await storage.loadSettings();
  if (settings.apiKey.trim().isEmpty) throw MissingKeyException();
  final client = clientOverride ?? GeminiClient(settings.apiKey.trim());
  final wait = backoff ?? (a) => Duration(milliseconds: 1500 * a);

  final inputs = <PhotoInput>[];
  for (var i = 0; i < photos.length; i++) {
    final bytes = await photos[i].readAsBytes();
    final ext = photos[i].path.toLowerCase();
    final mime = ext.endsWith('.png')
        ? 'image/png'
        : ext.endsWith('.webp')
            ? 'image/webp'
            : (ext.endsWith('.heic') || ext.endsWith('.heif'))
                ? 'image/heic'
                : 'image/jpeg';
    inputs.add(PhotoInput(labels[i], bytes, mimeType: mime));
  }

  return appraiseWithFallback(
    client: client,
    savedModel: settings.model.trim(),
    run: (model) => client.appraise(
      model: model,
      photos: inputs,
      extraInfo: extraInfo,
      box: box,
      papers: papers,
      webSearch: settings.webSearch,
    ),
    onStatus: onStatus,
    wait: wait,
    onModelWorked: (model) async {
      final now = await storage.loadSettings();
      await storage.saveSettings(Settings(
        apiKey: now.apiKey,
        model: model,
        webSearch: client.searchUnavailable ? false : now.webSearch,
      ));
    },
  );
}

/// Logica dei tentativi, separata per poterla testare.
Future<T> appraiseWithFallback<T>({
  required GeminiClient client,
  required String savedModel,
  required Future<T> Function(String model) run,
  required Future<void> Function(String model) onModelWorked,
  required Duration Function(int attempt) wait,
  void Function(String)? onStatus,
  int maxModels = 2,
  int triesPerModel = 2,
}) async {
  final tried = <String>{};
  List<String>? ranked;
  GeminiException? last;

  Future<String?> nextModel() async {
    if (tried.isEmpty && savedModel.isNotEmpty) return savedModel;
    ranked ??= await client.resolveModels();
    for (final m in ranked!) {
      if (!tried.contains(m)) return m;
    }
    return null;
  }

  while (tried.length < maxModels) {
    final model = await nextModel();
    if (model == null) break;
    tried.add(model);
    if (tried.length > 1) onStatus?.call('Provo un altro modello IA…');

    for (var attempt = 1; attempt <= triesPerModel; attempt++) {
      try {
        final r = await run(model);
        await onModelWorked(model);
        return r;
      } on GeminiException catch (e) {
        last = e;
        if (e.transient && attempt < triesPerModel) {
          onStatus?.call(e.status == -1
              ? 'Connessione interrotta, riprovo…'
              : 'Google è occupato, riprovo…');
          await Future<void>.delayed(wait(attempt));
          continue;
        }
        break;
      }
    }

    final e = last!;
    // Errori che un altro modello può risolvere: occupato, limite, sparito.
    final switchable = e.transient || e.status == 429 || e.status == 404;
    if (!switchable) throw e;
  }
  throw last ??
      GeminiException('Nessun modello Gemini adatto trovato per questa chiave.');
}

/// Aggiunge il prezzo di mercato dagli annunci eBay reali.
/// Restituisce la valutazione (eventualmente arricchita) e un avviso.
Future<(WatchAppraisal, String?)> addMarketPrice(
    Storage storage, WatchAppraisal a,
    {void Function(String)? onStatus}) async {
  if (!a.isWatch) return (a, null);
  final keys = await storage.loadEbay();
  if (keys.id.isEmpty || keys.secret.isEmpty) return (a, null);
  onStatus?.call('Leggo gli annunci reali su eBay…');
  try {
    final m = await lookupMarket(EbayClient(keys.id, keys.secret),
            brand: a.brand, model: a.model, reference: a.reference)
        .timeout(const Duration(seconds: 25));
    if (m == null) {
      return (a.withMarket(null), 'Nessun annuncio eBay trovato per questo '
          'modello: mostro la stima dell\'IA.');
    }
    final warn = m.reliable
        ? null
        : 'Solo ${m.count} annunci eBay trovati: mostro la stima dell\'IA.';
    return (a.withMarket(m), warn);
  } on TimeoutException {
    return (a, 'eBay non ha risposto in tempo: mostro la stima dell\'IA.');
  } catch (e) {
    return (a, 'eBay non disponibile ($e). Mostro la stima dell\'IA.');
  }
}
