import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../conductor/data/conductor_repository.dart';
import '../data/search_repository.dart';

/// Recherche dans les sujets, les lignes de conducteur (titre et texte), les discussions et les sons.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<SearchHit>? _hits;
  bool _loading = false;
  bool _failed = false;
  int _seq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() {
        _hits = null;
        _loading = false;
        _failed = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(value));
  }

  Future<void> _run(String value) async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final hits = await ref.read(searchRepositoryProvider).search(value);
      if (!mounted || seq != _seq) return;
      setState(() {
        _hits = hits;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  void _open(SearchHit h) {
    if (h.date != null) ref.read(selectedDateProvider.notifier).set(h.date!);
    switch (h.kind) {
      case SearchKind.proposal:
        if (h.proposalApproved) {
          context.push('/forum/${h.proposalId}/thread');
        } else {
          context.go('/forum');
        }
      case SearchKind.line:
        context.push('/conductor/${h.conductorId}/line/${h.lineId}');
      case SearchKind.message:
        if (h.lineId != null && h.conductorId != null) {
          context.push('/conductor/${h.conductorId}/line/${h.lineId}');
        } else if (h.proposalId != null) {
          context.push('/forum/${h.proposalId}/thread');
        }
      case SearchKind.sound:
        context.go('/sound');
    }
  }

  IconData _icon(SearchKind k) => switch (k) {
    SearchKind.proposal => Icons.lightbulb_outline,
    SearchKind.line => Icons.view_list_outlined,
    SearchKind.message => Icons.chat_bubble_outline,
    SearchKind.sound => Icons.audiotrack,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hits = _hits;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: (v) {
            if (v.trim().length >= 2) _run(v);
          },
          decoration: const InputDecoration(
            hintText: 'Rechercher un sujet, un texte, un son…',
            border: InputBorder.none,
            filled: false,
          ),
        ),
      ),
      body: Builder(
        builder: (_) {
          if (_loading) return const Center(child: CircularProgressIndicator());
          if (_failed) {
            return const Center(
              child: Text('Recherche impossible. Vérifiez le réseau.'),
            );
          }
          if (hits == null) {
            return Center(
              child: Text(
                'Saisissez au moins 2 caractères.',
                style: TextStyle(color: c.mutedForeground),
              ),
            );
          }
          if (hits.isEmpty) {
            return Center(
              child: Text(
                'Aucun résultat.',
                style: TextStyle(color: c.mutedForeground),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(Space.lg),
            children: [
              for (final kind in SearchKind.values)
                if (hits.any((h) => h.kind == kind)) ...[
                  Padding(
                    padding: const EdgeInsets.only(
                      top: Space.md,
                      bottom: Space.sm,
                    ),
                    child: Text(
                      kind.label,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  for (final h in hits.where((h) => h.kind == kind))
                    Card(
                      child: ListTile(
                        leading: Icon(_icon(h.kind), color: c.success),
                        title: Text(
                          h.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          [
                            if (h.subtitle != null && h.subtitle!.isNotEmpty)
                              h.subtitle!,
                            if (h.date != null)
                              DateFormat('dd/MM/yyyy').format(h.date!),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _open(h),
                      ),
                    ),
                ],
            ],
          );
        },
      ),
    );
  }
}
