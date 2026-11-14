import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where the app keeps Empower exports and account mappings
/// (`imports/empower/` in Application Support), never in a repo. Each kind
/// of export is saved under its own file-name prefix, newest kept beside
/// the older ones.
class const EmpowerImportsFolder() {
  Future<Directory> directory() async {
    final supportDirectory = await getApplicationSupportDirectory();
    return Directory(p.join(supportDirectory.path, 'imports', 'empower'))
      ..createSync(recursive: true);
  }

  /// Copies [sourcePath] (`~` allowed) in as `<prefix><timestamp>.json`.
  Future<File> saveExport(String sourcePath, {required String prefix}) async {
    final String home = Platform.environment['HOME'] ?? '';
    final source = File(sourcePath.replaceFirst(RegExp(r'^~'), home));
    if (!source.existsSync()) throw ArgumentError('No file at $sourcePath.');
    final String stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '')
        .split('.')
        .first;
    return source.copySync(
      p.join((await directory()).path, '$prefix$stamp.json'),
    );
  }

  /// Saved exports with [prefix], newest first.
  Future<List<File>> savedExports({required String prefix}) async => [
    for (final entity in (await directory()).listSync())
      if (entity is File && p.basename(entity.path).startsWith(prefix)) entity,
  ]..sort((left, right) => right.path.compareTo(left.path));

  /// [sourcePath] saved in, or the newest saved export when it is null.
  Future<File> exportFrom(String? sourcePath, {required String prefix}) async {
    if (sourcePath != null) return saveExport(sourcePath, prefix: prefix);
    return (await savedExports(prefix: prefix)).firstOrNull ??
        (throw ArgumentError('No saved $prefix export; pass "file".'));
  }

  Future<Map<String, dynamic>> readJson(String fileName) async {
    final file = File(p.join((await directory()).path, fileName));
    if (!file.existsSync()) return {};
    return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  }

  Future<void> writeJson(String fileName, Map<String, Object?> json) async {
    File(p.join((await directory()).path, fileName))
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
  }
}
