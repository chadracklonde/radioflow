import 'package:intl/intl.dart';

/// Nommage automatique des fichiers audio : `[Position]_[Nom_Original]_[Date].[ext]`
/// Exemple : `03_Reportage_Marche_2026-09-09.mp3`.
/// Même règle que la fonction SQL `public.audio_stored_name`.
String audioStoredName({
  required int position,
  required String originalName,
  required DateTime date,
}) {
  final dot = RegExp(r'\.([A-Za-z0-9]+)$').firstMatch(originalName);
  final ext = dot?.group(1)?.toLowerCase();
  var base = dot == null ? originalName : originalName.substring(0, dot.start);
  base = _stripAccents(base)
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  if (base.isEmpty) base = 'audio';
  final pos = position.toString().padLeft(2, '0');
  final day = DateFormat('yyyy-MM-dd').format(date);
  return '${pos}_${base}_$day${ext == null ? '' : '.$ext'}';
}

const _from = 'àâäáãåéèêëíìîïóòôöõúùûüçñÿÀÂÄÁÃÅÉÈÊËÍÌÎÏÓÒÔÖÕÚÙÛÜÇÑ';
const _to = 'aaaaaaeeeeiiiiooooouuuucnyAAAAAAEEEEIIIIOOOOOUUUUCN';

String _stripAccents(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    final i = _from.indexOf(ch);
    if (i >= 0) {
      b.write(_to[i]);
    } else if (ch == 'œ') {
      b.write('oe');
    } else if (ch == 'Œ') {
      b.write('OE');
    } else if (ch == 'æ') {
      b.write('ae');
    } else if (ch == 'Æ') {
      b.write('AE');
    } else {
      b.write(ch);
    }
  }
  return b.toString();
}

abstract final class AudioRules {
  static const extensions = ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac', 'wma'];

  /// Limite du bucket sur le plan gratuit (50 Mo).
  static const maxBytes = 50 * 1024 * 1024;

  /// Message d'erreur en français si le fichier est refusé, sinon null.
  static String? validate({required String name, required int size}) {
    final m = RegExp(r'\.([A-Za-z0-9]+)$').firstMatch(name);
    final ext = m?.group(1)?.toLowerCase();
    if (ext == null || !extensions.contains(ext)) {
      return 'Format non pris en charge. Formats acceptés : ${extensions.join(', ')}.';
    }
    if (size <= 0) return 'Le fichier est vide.';
    if (size > maxBytes) return 'Fichier trop volumineux (50 Mo maximum).';
    return null;
  }
}
