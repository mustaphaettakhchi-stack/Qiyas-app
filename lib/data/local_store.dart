import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/models.dart';

/// Stockage local en fichier JSON dans le dossier privé de l'application.
/// Les photos sont copiées dans un sous-dossier « photos ».
class LocalStore {
  static const _fileName = 'qiyas_data.json';

  Future<Directory> _dir() => getApplicationDocumentsDirectory();

  Future<AppData?> load() async {
    try {
      final f = File('${(await _dir()).path}/$_fileName');
      if (!await f.exists()) return null;
      final json = jsonDecode(await f.readAsString());
      return AppData.fromJson(Map<String, dynamic>.from(json as Map));
    } catch (_) {
      return null;
    }
  }

  Future<void> save(AppData data) async {
    final dir = await _dir();
    final f = File('${dir.path}/$_fileName');
    final tmp = File('${dir.path}/$_fileName.tmp');
    await tmp.writeAsString(jsonEncode(data.toJson()), flush: true);
    await tmp.rename(f.path);
  }

  Future<void> clear() async {
    final f = File('${(await _dir()).path}/$_fileName');
    if (await f.exists()) await f.delete();
  }

  /// Copie une image choisie (cache temporaire) vers le stockage durable.
  Future<String> keepPhoto(String sourcePath, String id) async {
    final dir = Directory('${(await _dir()).path}/photos');
    if (!await dir.exists()) await dir.create(recursive: true);
    final ext = sourcePath.contains('.') ? sourcePath.substring(sourcePath.lastIndexOf('.')) : '.jpg';
    final dest = '${dir.path}/$id$ext';
    await File(sourcePath).copy(dest);
    return dest;
  }

  /// Exporte toutes les données dans un fichier JSON (droit d'accès, loi 09-08).
  Future<String> exportFile(AppData data) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/qiyas_export_${DateTime.now().millisecondsSinceEpoch}.json');
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data.toJson()));
    return f.path;
  }
}
