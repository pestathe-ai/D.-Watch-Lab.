import 'dart:io';

import '../models/appraisal.dart';
import 'gemini_client.dart';
import 'storage.dart';

class MissingKeyException implements Exception {}

/// Esegue una valutazione completa: legge impostazioni, sceglie il modello,
/// invia le foto e restituisce il risultato.
Future<WatchAppraisal> runAppraisal({
  required Storage storage,
  required List<File> photos,
  required List<String> labels,
  String extraInfo = '',
  bool box = false,
  bool papers = false,
}) async {
  final settings = await storage.loadSettings();
  if (settings.apiKey.trim().isEmpty) throw MissingKeyException();
  final client = GeminiClient(settings.apiKey.trim());

  var model = settings.model.trim();
  if (model.isEmpty) {
    model = await client.resolveModel();
    await storage.saveSettings(Settings(
        apiKey: settings.apiKey, model: model, webSearch: settings.webSearch));
  }

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

  try {
    return await client.appraise(
      model: model,
      photos: inputs,
      extraInfo: extraInfo,
      box: box,
      papers: papers,
      webSearch: settings.webSearch,
    );
  } on GeminiException catch (e) {
    // Modello sparito (Google li ritira): ne cerco uno nuovo e riprovo.
    if (e.message.startsWith('Modello non trovato')) {
      final fresh = await client.resolveModel();
      await storage.saveSettings(Settings(
          apiKey: settings.apiKey,
          model: fresh,
          webSearch: settings.webSearch));
      return client.appraise(
        model: fresh,
        photos: inputs,
        extraInfo: extraInfo,
        box: box,
        papers: papers,
        webSearch: settings.webSearch,
      );
    }
    rethrow;
  }
}
