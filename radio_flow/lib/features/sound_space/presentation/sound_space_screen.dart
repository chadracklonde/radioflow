import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/date_bar.dart';
import '../../auth/data/profile_repository.dart';
import '../../conductor/data/conductor_repository.dart';
import '../../conductor/domain/conductor_models.dart';
import '../data/audio_services.dart';
import '../data/sound_repository.dart';
import '../domain/sound_file.dart';

/// Espace Son : fichiers audio de la journée, classés par édition et par position.
class SoundSpaceScreen extends ConsumerWidget {
  const SoundSpaceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(selectedDateProvider);
    final iso = isoDate(date);
    final files = ref.watch(soundFilesProvider(iso));
    final names = ref.watch(authorNamesProvider).value ?? const {};
    final c = context.colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          DateBar(date: date),
          Expanded(
            child: files.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off, size: 40, color: c.mutedForeground),
                    const SizedBox(height: Space.md),
                    const Text('Impossible de charger les fichiers.'),
                    TextButton(
                      onPressed: () => ref.invalidate(soundFilesProvider(iso)),
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(Space.xl),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.library_music_outlined,
                            size: 40,
                            color: c.mutedForeground,
                          ),
                          const SizedBox(height: Space.md),
                          Text(
                            'Aucun fichier audio ce jour-là.\nLes sons envoyés dans les fils du conducteur apparaissent ici, renommés automatiquement.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: c.mutedForeground),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                // Regroupement par édition, en conservant l'ordre (heure puis position).
                final groups = <String, List<SoundFile>>{};
                for (final f in list) {
                  groups.putIfAbsent(f.conductorId, () => []).add(f);
                }
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(soundFilesProvider(iso).future),
                  child: ListView(
                    padding: const EdgeInsets.all(Space.lg),
                    children: [
                      for (final g in groups.values) ...[
                        _GroupHeader(file: g.first, count: g.length),
                        const SizedBox(height: Space.sm),
                        for (final f in g) ...[
                          _FileTile(
                            file: f,
                            uploader: names[f.uploadedBy] ?? 'Membre',
                          ),
                          const SizedBox(height: Space.sm),
                        ],
                        const SizedBox(height: Space.md),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.file, required this.count});
  final SoundFile file;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        if (file.broadcastTime != null) ...[
          Text(
            file.broadcastTime!,
            style: text.titleMedium?.copyWith(
              fontFamily: 'FiraCode',
              color: c.success,
            ),
          ),
          const SizedBox(width: Space.md),
        ],
        Expanded(child: Text(file.conductorTitle, style: text.titleMedium)),
        Text('$count fichier${count > 1 ? 's' : ''}', style: text.bodySmall),
      ],
    );
  }
}

class _FileTile extends ConsumerWidget {
  const _FileTile({required this.file, required this.uploader});
  final SoundFile file;
  final String uploader;

  void _toast(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    try {
      final Uint8List bytes = await ref
          .read(soundRepositoryProvider)
          .download(file.storagePath);
      final saved = await ref
          .read(audioFileServiceProvider)
          .save(fileName: file.storedName, bytes: bytes);
      if (context.mounted && saved) {
        _toast(context, '${file.storedName} enregistré.');
      }
    } catch (_) {
      if (context.mounted) {
        _toast(context, 'Téléchargement impossible. Réessayez.');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final playing = ref.watch(nowPlayingProvider) == file.storagePath;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm,
        ),
        child: Row(
          children: [
            IconButton.filledTonal(
              tooltip: playing ? 'Arrêter la lecture' : 'Écouter',
              icon: Icon(playing ? Icons.stop : Icons.play_arrow),
              onPressed: () async {
                try {
                  await ref
                      .read(nowPlayingProvider.notifier)
                      .toggle(
                        file.storagePath,
                        ref.read(audioPlayerProvider),
                        ref.read(soundRepositoryProvider),
                      );
                } catch (_) {
                  if (context.mounted) {
                    _toast(context, 'Lecture impossible. Réessayez.');
                  }
                }
              },
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.storedName,
                    style: text.bodyMedium?.copyWith(
                      fontFamily: 'FiraCode',
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    '${file.lineTitle} · $uploader · ${DateFormat('HH:mm', 'fr').format(file.uploadedAt.toLocal())}'
                    '${file.duration != null ? ' · ${formatDuration(file.duration!)}' : ''}',
                    style: text.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Télécharger',
              icon: Icon(Icons.download, color: c.mutedForeground),
              onPressed: () => _download(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}
