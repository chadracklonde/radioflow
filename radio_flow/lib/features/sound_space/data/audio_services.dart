import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/utils/audio_naming.dart';

class PickedAudio {
  const PickedAudio({
    required this.name,
    required this.size,
    required this.readBytes,
  });
  final String name;
  final int size;
  final Future<Uint8List> Function() readBytes;
}

/// Sélection et enregistrement de fichiers (isolé pour les tests).
abstract class AudioFileService {
  Future<PickedAudio?> pick();

  /// Enregistre sur l'appareil; renvoie false si l'utilisateur annule.
  Future<bool> save({required String fileName, required Uint8List bytes});
}

class FilePickerAudioFileService implements AudioFileService {
  @override
  Future<PickedAudio?> pick() async {
    final f = await FilePicker.pickFile(
      dialogTitle: 'Choisir un fichier audio',
      type: FileType.custom,
      allowedExtensions: AudioRules.extensions,
    );
    if (f == null) return null;
    return PickedAudio(
      name: f.name,
      size: await f.length() ?? 0,
      readBytes: f.readAsBytes,
    );
  }

  @override
  Future<bool> save({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final uri = await FilePicker.saveFile(fileName: fileName, bytes: bytes);
    return uri != null;
  }
}

final audioFileServiceProvider = Provider<AudioFileService>(
  (ref) => FilePickerAudioFileService(),
);

/// Lecture audio (isolée pour les tests).
abstract class AudioPlayerService {
  Future<void> play(String url);
  Future<void> stop();

  /// Émet quand la lecture arrive à la fin.
  Stream<void> get completed;
  void dispose();
}

class JustAudioPlayerService implements AudioPlayerService {
  final _player = AudioPlayer();

  @override
  Future<void> play(String url) async {
    await _player.setUrl(url);
    unawaited(_player.play());
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  Stream<void> get completed => _player.processingStateStream.where(
    (s) => s == ProcessingState.completed,
  );

  @override
  void dispose() => _player.dispose();
}

final audioPlayerProvider = Provider<AudioPlayerService>((ref) {
  final service = JustAudioPlayerService();
  ref.onDispose(service.dispose);
  return service;
});
