import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Stockage disque des morceaux telecharges pour l'ecoute hors ligne.
///
/// Un fichier par piste dans `<documents>/offline_audio/`, nomme par l'id de
/// la piste (l'extension est reprise de l'URL). Le telechargement passe par
/// un fichier `.part` renomme a la fin, pour ne jamais laisser un fichier
/// tronque se faire passer pour une piste complete.
class OfflineAudioStore {
  final Future<Directory> Function() _baseDirectory;

  OfflineAudioStore({Future<Directory> Function()? baseDirectory})
      : _baseDirectory = baseDirectory ?? getApplicationDocumentsDirectory;

  static const _partSuffix = '.part';

  Future<Directory> _dir() async {
    final base = await _baseDirectory();
    final dir = Directory('${base.path}/offline_audio');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _extensionOf(String url) {
    final path = Uri.parse(url).path;
    final dot = path.lastIndexOf('.');
    if (dot <= path.lastIndexOf('/')) return '.mp3';
    final ext = path.substring(dot).toLowerCase();
    return ext.length <= 5 ? ext : '.mp3';
  }

  /// Ids des pistes deja telechargees (scan du dossier au demarrage).
  Future<Set<String>> cachedTrackIds() async {
    final dir = await _dir();
    final ids = <String>{};
    await for (final entry in dir.list()) {
      if (entry is! File) continue;
      final name = entry.uri.pathSegments.last;
      if (name.endsWith(_partSuffix)) continue;
      final dot = name.lastIndexOf('.');
      ids.add(dot == -1 ? name : name.substring(0, dot));
    }
    return ids;
  }

  /// Fichier temporaire ou ecrire le telechargement de [trackId].
  Future<File> partFileFor(String trackId, String url) async {
    final dir = await _dir();
    return File('${dir.path}/$trackId${_extensionOf(url)}$_partSuffix');
  }

  /// Promeut le `.part` en fichier definitif une fois le telechargement fini.
  Future<File> commit(File partFile) {
    final path = partFile.path;
    return partFile.rename(path.substring(0, path.length - _partSuffix.length));
  }

  /// Chemin local de la piste, ou null si elle n'est pas telechargee.
  Future<String?> localPathFor(String trackId) async {
    final dir = await _dir();
    await for (final entry in dir.list()) {
      if (entry is! File) continue;
      final name = entry.uri.pathSegments.last;
      if (name.endsWith(_partSuffix)) continue;
      final dot = name.lastIndexOf('.');
      final id = dot == -1 ? name : name.substring(0, dot);
      if (id == trackId) return entry.path;
    }
    return null;
  }

  Future<void> delete(String trackId) async {
    final path = await localPathFor(trackId);
    if (path != null) {
      await File(path).delete();
    }
  }
}
