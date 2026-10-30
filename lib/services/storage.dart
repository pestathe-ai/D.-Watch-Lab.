import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/appraisal.dart';
import '../models/market.dart';

class Settings {
  final String apiKey;
  final String model;
  final bool webSearch;
  const Settings({this.apiKey = '', this.model = '', this.webSearch = false});
}

class Storage {
  static const _kKey = 'api_key';
  static const _kModel = 'model';
  static const _kWeb = 'web_search';
  static const _kCollection = 'collection_v1';

  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  Future<Settings> loadSettings() async => Settings(
        apiKey: await _prefs.getString(_kKey) ?? '',
        model: await _prefs.getString(_kModel) ?? '',
        webSearch: await _prefs.getBool(_kWeb) ?? false,
      );

  Future<void> saveSettings(Settings s) async {
    await _prefs.setString(_kKey, s.apiKey.trim());
    await _prefs.setString(_kModel, s.model.trim());
    await _prefs.setBool(_kWeb, s.webSearch);
  }

  static const _kEbayId = 'ebay_client_id';
  static const _kEbaySecret = 'ebay_client_secret';

  Future<({String id, String secret})> loadEbay() async => (
        id: await _prefs.getString(_kEbayId) ?? '',
        secret: await _prefs.getString(_kEbaySecret) ?? '',
      );

  Future<void> saveEbay(String id, String secret) async {
    await _prefs.setString(_kEbayId, id.trim());
    await _prefs.setString(_kEbaySecret, secret.trim());
  }

  static const _kFastModel = 'fast_model';
  static const _kFastMode = 'fast_mode';
  static const _kMarketCache = 'market_cache_v1';

  Future<String> loadFastModel() async =>
      await _prefs.getString(_kFastModel) ?? '';
  Future<void> saveFastModel(String m) => _prefs.setString(_kFastModel, m);

  /// Modalità veloce: riconoscimento con il modello leggero (default sì).
  Future<bool> loadFastMode() async => await _prefs.getBool(_kFastMode) ?? true;
  Future<void> saveFastMode(bool v) => _prefs.setBool(_kFastMode, v);

  /// Prezzi eBay già calcolati (validi 24 ore), per chiave di ricerca.
  Future<MarketPrice?> cachedMarket(String key) async {
    try {
      final raw = await _prefs.getString(_kMarketCache);
      if (raw == null) return null;
      final map = jsonDecode(raw) as Map;
      final j = map[key];
      if (j is! Map) return null;
      final m = MarketPrice.fromJson(Map<String, dynamic>.from(j));
      if (DateTime.now().difference(m.date) > const Duration(hours: 24)) {
        return null;
      }
      return m;
    } catch (_) {
      return null;
    }
  }

  Future<void> cacheMarket(String key, MarketPrice m) async {
    try {
      final raw = await _prefs.getString(_kMarketCache);
      final map = raw == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(raw) as Map);
      map[key] = m.toJson();
      // Tiene solo le 40 ricerche più recenti.
      if (map.length > 40) {
        final keys = map.keys.toList()
          ..sort((a, b) => ((map[a] as Map)['date'] as String)
              .compareTo((map[b] as Map)['date'] as String));
        for (final k in keys.take(map.length - 40)) {
          map.remove(k);
        }
      }
      await _prefs.setString(_kMarketCache, jsonEncode(map));
    } catch (_) {}
  }

  Future<List<SavedValuation>> loadCollection() async {
    final list =
        SavedValuation.listFromJson(await _prefs.getString(_kCollection));
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  Future<void> _saveCollection(List<SavedValuation> items) =>
      _prefs.setString(_kCollection, SavedValuation.listToJson(items));

  /// Copia le foto nella cartella dell'app e salva la valutazione.
  Future<SavedValuation> add(WatchAppraisal a, List<File> photos,
      {String note = '',
      String? replaceId,
      List<String> labels = const [],
      bool box = false,
      bool papers = false,
      String extraInfo = ''}) async {
    final dir = await getApplicationDocumentsDirectory();
    final id = replaceId ?? DateTime.now().microsecondsSinceEpoch.toString();
    final folder = Directory(p.join(dir.path, 'watches', id));
    await folder.create(recursive: true);
    final saved = <String>[];
    for (var i = 0; i < photos.length; i++) {
      final src = photos[i];
      final dest = p.join(folder.path,
          '${DateTime.now().millisecondsSinceEpoch}_$i${p.extension(src.path)}');
      if (p.isWithin(folder.path, src.path)) {
        saved.add(src.path);
      } else if (src.path == dest) {
        saved.add(dest);
      } else {
        saved.add((await src.copy(dest)).path);
      }
    }
    final all = await loadCollection();
    final old = all.where((e) => e.id == id).firstOrNull;
    final v = SavedValuation(
        id: id,
        date: DateTime.now(),
        photoPaths: saved,
        appraisal: a,
        note: note.isEmpty ? (old?.note ?? '') : note,
        history: old?.timeline ?? const [],
        photoLabels: labels,
        box: box,
        papers: papers,
        extraInfo: extraInfo);
    all.removeWhere((e) => e.id == id);
    all.insert(0, v);
    await _saveCollection(all);
    return v;
  }

  Future<void> delete(String id) async {
    final all = await loadCollection();
    all.removeWhere((e) => e.id == id);
    await _saveCollection(all);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory(p.join(dir.path, 'watches', id));
      if (await folder.exists()) await folder.delete(recursive: true);
    } catch (_) {}
  }
}
