import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/appraisal.dart';

class Settings {
  final String apiKey;
  final String model;
  final bool webSearch;
  const Settings({this.apiKey = '', this.model = '', this.webSearch = true});
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
        webSearch: await _prefs.getBool(_kWeb) ?? true,
      );

  Future<void> saveSettings(Settings s) async {
    await _prefs.setString(_kKey, s.apiKey.trim());
    await _prefs.setString(_kModel, s.model.trim());
    await _prefs.setBool(_kWeb, s.webSearch);
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
