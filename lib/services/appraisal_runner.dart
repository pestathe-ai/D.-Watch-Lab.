import 'dart:io';

import '../models/appraisal.dart';
import '../models/market.dart';
import 'alt_client.dart';
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
  String? hint,
}) async {
  final settings = await storage.loadSettings();
  if (settings.apiKey.trim().isEmpty) throw MissingKeyException();
  final client = clientOverride ?? GeminiClient(settings.apiKey.trim());
  final wait = backoff ?? (a) => Duration(seconds: 2 * a);

  final inputs = await loadPhotos(photos, labels);
  final info = [
    if (hint != null && hint.trim().isNotEmpty)
      'Identificazione preliminare da verificare: ${hint.trim()}',
    if (extraInfo.trim().isNotEmpty) extraInfo.trim(),
  ].join('. ');

  final backups = await storage.loadBackupKeys();
  final alt = await storage.loadAlt();

  try {
    return await tryInOrder<WatchAppraisal>([
      (
        '',
        () => appraiseWithFallback(
              client: client,
              savedModel: settings.model.trim(),
              run: (model) => client.appraise(
                model: model,
                photos: inputs,
                extraInfo: info,
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
            )
      ),
      // Chiavi Gemini di riserva: ogni progetto Google ha i suoi limiti.
      for (var i = 0; i < backups.length; i++)
        (
          'Gemini al limite: uso la chiave di riserva ${i + 1}…',
          () {
            final c = GeminiClient(backups[i]);
            return appraiseWithFallback(
              client: c,
              savedModel: '',
              run: (model) => c.appraise(
                model: model,
                photos: inputs,
                extraInfo: info,
                box: box,
                papers: papers,
                webSearch: false,
              ),
              wait: wait,
              onModelWorked: (_) async {},
            );
          }
        ),
      // Servizio alternativo gratuito.
      if (alt != null)
        (
          'Gemini al limite: uso ${alt.provider.label}…',
          () => AltClient(alt).appraise(
                photos: inputs,
                extraInfo: info,
                box: box,
                papers: papers,
              )
        ),
    ], onStatus: onStatus);
  } on GeminiException catch (e) {
    if (e.status == 429 && backups.isEmpty && alt == null) {
      throw GeminiException('${e.message}\n\nPer continuare subito, aggiungi '
          'una riserva gratuita in Impostazioni → Riserva IA.', 429);
    }
    rethrow;
  }
}

Future<List<PhotoInput>> loadPhotos(
    List<File> photos, List<String> labels) async {
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
  return inputs;
}

/// Riconoscimento lampo (marca, modello, referenza). In modalità veloce usa
/// il modello più leggero. Restituisce null se non riesce: in quel caso si
/// procede con l'analisi completa come prima.
Future<WatchAppraisal?> runIdentify({
  required Storage storage,
  required List<File> photos,
  required List<String> labels,
  String extraInfo = '',
}) async {
  final settings = await storage.loadSettings();
  if (settings.apiKey.trim().isEmpty) throw MissingKeyException();
  final client = GeminiClient(settings.apiKey.trim());
  try {
    var model = settings.model.trim();
    if (await storage.loadFastMode()) {
      model = await storage.loadFastModel();
      if (model.isEmpty) {
        model = await client.resolveFastModel();
        await storage.saveFastModel(model);
      }
    }
    if (model.isEmpty) model = await client.resolveModel();
    final inputs = await loadPhotos(photos, labels);
    final r = await client.identify(
        model: model, photos: inputs, extraInfo: extraInfo);
    if (r.isWatch && r.brand.isEmpty && r.model.isEmpty) return null;
    return r;
  } on GeminiException catch (e) {
    // Modello leggero sparito: lo ricerco la prossima volta.
    if (e.status == 404) await storage.saveFastModel('');
    return null;
  } catch (_) {
    return null;
  }
}

/// Logica dei tentativi, separata per poterla testare.
Future<T> appraiseWithFallback<T>({
  required GeminiClient client,
  required String savedModel,
  required Future<T> Function(String model) run,
  required Future<void> Function(String model) onModelWorked,
  required Duration Function(int attempt) wait,
  void Function(String)? onStatus,
  int maxModels = 3,
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
          onStatus?.call('Google è occupato, riprovo…');
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
    final key = normalize(
        '${marketQuery(brand: a.brand, model: a.model, reference: a.reference)} '
        '${a.hints.cacheKey}');
    var m = await storage.cachedMarket(key);
    if (m == null) {
      m = await lookupMarket(EbayClient(keys.id, keys.secret),
          brand: a.brand,
          model: a.model,
          reference: a.reference,
          hints: a.hints);
      if (m != null) await storage.cacheMarket(key, m);
    }
    if (m == null) {
      return (a.withMarket(null), 'Nessun annuncio eBay trovato per questo '
          'modello: mostro la stima dell\'IA.');
    }
    final withM = a.withMarket(m);
    final warn = withM.marketMismatch
        ? 'Gli annunci eBay trovati sembrano di modelli diversi: mostro la '
            'stima dell\'IA.'
        : m.reliable
            ? null
            : 'Solo ${m.count} annunci eBay trovati: mostro la stima dell\'IA.';
    return (withM, warn);
  } catch (e) {
    return (a, 'eBay non disponibile ($e). Mostro la stima dell\'IA.');
  }
}
