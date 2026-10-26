import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/icon_label.dart';
import '../../auth/data/profile_repository.dart';
import '../data/team_repository.dart';

/// Gestion de l'équipe : réservée au rédacteur en chef.
class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(profileProvider).value;
    final team = ref.watch(teamProvider);
    final c = context.colors;

    if (me != null && !me.isSuperAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Équipe')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(Space.xl),
            child: Text('Réservé au super administrateur.'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Équipe')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddMemberForm(context),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Ajouter un membre'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: team.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off, size: 40, color: c.mutedForeground),
                    const SizedBox(height: Space.md),
                    const Text('Impossible de charger l’équipe.'),
                    TextButton(
                      onPressed: () => ref.invalidate(teamProvider),
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
              data: (members) => RefreshIndicator(
                onRefresh: () => ref.refresh(teamProvider.future),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    Space.lg,
                    Space.lg,
                    96,
                  ),
                  itemCount: members.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
                  itemBuilder: (_, i) => _MemberTile(
                    member: members[i],
                    isMe: members[i].id == me?.id,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({required this.member, required this.isMe});
  final TeamMember member;
  final bool isMe;

  String get _initials {
    final parts = member.fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((x) => x.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : ''))
        .toUpperCase();
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      ref.invalidate(teamProvider);
    } on TeamException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Action impossible. Vérifiez le réseau et réessayez.'),
        ),
      );
    }
  }

  Future<void> _confirmToggle(BuildContext context, WidgetRef ref) async {
    final deactivate = member.active;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          deactivate
              ? 'Désactiver ${member.fullName} ?'
              : 'Réactiver ${member.fullName} ?',
        ),
        content: Text(
          deactivate
              ? 'Ce membre ne pourra plus se connecter. Ses contenus restent en place. Vous pourrez le réactiver à tout moment.'
              : 'Ce membre pourra de nouveau se connecter avec son mot de passe actuel.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(deactivate ? 'Désactiver' : 'Réactiver'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await _run(
        context,
        ref,
        () =>
            ref.read(teamRepositoryProvider).setActive(member.id, !deactivate),
      );
    }
  }

  Future<void> _pickDeputy(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      helpText: 'Suppléance de ${member.fullName} jusqu’au…',
      initialDate: now.add(const Duration(days: 7)),
      firstDate: now.add(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 89)),
    );
    if (picked == null || !context.mounted) return;
    // jusqu'à la fin de la journée choisie
    final until = DateTime(picked.year, picked.month, picked.day, 23, 59);
    await _run(
      context,
      ref,
      () => ref.read(teamRepositoryProvider).setDeputy(member.id, until),
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Réinitialiser le mot de passe de ${member.fullName} ?'),
        content: const Text(
          'Un nouveau mot de passe provisoire sera créé et l’ancien cessera de fonctionner. Transmettez-le au membre de manière privée.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Réinitialiser'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final created = await ref
          .read(teamRepositoryProvider)
          .resetPassword(member.id);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _CredentialsDialog(
          created: CreatedMember(
            id: created.id,
            email: member.email,
            tempPassword: created.tempPassword,
          ),
          title: 'Mot de passe réinitialisé',
        ),
      );
    } on TeamException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Réinitialisation impossible. Réessayez.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final dim = !member.active;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm,
        ),
        child: Row(
          children: [
            ExcludeSemantics(
              child: CircleAvatar(
                backgroundColor: c.muted,
                child: Text(
                  _initials,
                  style: TextStyle(
                    color: dim ? c.mutedForeground : c.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isMe ? '${member.fullName} (vous)' : member.fullName,
                    style: text.bodyLarge?.copyWith(
                      color: dim ? c.mutedForeground : null,
                    ),
                  ),
                  Text(
                    member.email,
                    style: text.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: Space.xs),
                  Wrap(
                    spacing: Space.md,
                    runSpacing: Space.xs,
                    children: [
                      IconLabel(
                        icon: Icons.badge_outlined,
                        label: member.isSuperAdmin
                            ? 'Super administrateur'
                            : member.role.label,
                        color: c.mutedForeground,
                      ),
                      if (member.isDeputy)
                        IconLabel(
                          icon: Icons.swap_horiz,
                          label:
                              'Suppléant jusqu’au ${DateFormat('dd/MM/yyyy').format(member.deputyUntil!)}',
                          color: c.warning,
                        ),
                      if (dim)
                        IconLabel(
                          icon: Icons.block,
                          label: 'Désactivé',
                          color: c.danger,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            // Le compte super administrateur n'est modifiable par personne depuis l'application.
            if (!member.isSuperAdmin)
              PopupMenuButton<String>(
                tooltip: 'Actions pour ${member.fullName}',
                onSelected: (v) async {
                  if (v == 'toggle') {
                    await _confirmToggle(context, ref);
                  } else if (v == 'deputy') {
                    await _pickDeputy(context, ref);
                  } else if (v == 'deputy_clear') {
                    await _run(
                      context,
                      ref,
                      () => ref
                          .read(teamRepositoryProvider)
                          .setDeputy(member.id, null),
                    );
                  } else if (v == 'reset') {
                    await _confirmReset(context, ref);
                  } else {
                    final role = UserRole.values.byName(v);
                    await _run(
                      context,
                      ref,
                      () => ref
                          .read(teamRepositoryProvider)
                          .setRole(member.id, role),
                    );
                  }
                },
                itemBuilder: (_) => [
                  for (final r in UserRole.values)
                    CheckedPopupMenuItem(
                      value: r.name,
                      checked: r == member.role,
                      child: Text(r.label),
                    ),
                  if (!isMe &&
                      member.active &&
                      member.role != UserRole.admin) ...[
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'deputy',
                      child: Text(
                        member.isDeputy
                            ? 'Modifier la suppléance'
                            : 'Désigner suppléant du rédacteur en chef',
                      ),
                    ),
                    if (member.isDeputy)
                      const PopupMenuItem(
                        value: 'deputy_clear',
                        child: Text('Mettre fin à la suppléance'),
                      ),
                  ],
                  if (!isMe)
                    const PopupMenuItem(
                      value: 'reset',
                      child: Text('Réinitialiser le mot de passe'),
                    ),
                  if (!isMe) ...[
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'toggle',
                      child: Text(
                        member.active
                            ? 'Désactiver le compte'
                            : 'Réactiver le compte',
                      ),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> showAddMemberForm(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => const _AddMemberForm(),
  );
}

class _AddMemberForm extends ConsumerStatefulWidget {
  const _AddMemberForm();

  @override
  ConsumerState<_AddMemberForm> createState() => _AddMemberFormState();
}

class _AddMemberFormState extends ConsumerState<_AddMemberForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  UserRole _role = UserRole.journalist;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await ref
          .read(teamRepositoryProvider)
          .create(email: _email.text, fullName: _name.text, role: _role);
      ref.invalidate(teamProvider);
      if (!mounted) return;
      final navigator = Navigator.of(context);
      navigator.pop();
      await showDialog<void>(
        context: navigator.context,
        barrierDismissible: false,
        builder: (_) => _CredentialsDialog(created: created),
      );
    } on TeamException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'Création impossible. Vérifiez le réseau et réessayez.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Space.lg,
        0,
        Space.lg,
        Space.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Ajouter un membre',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: Space.lg),
              TextFormField(
                controller: _name,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nom complet'),
                validator: (v) => (v == null || v.trim().length < 2)
                    ? 'Saisissez le nom complet.'
                    : null,
              ),
              const SizedBox(height: Space.lg),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (v) {
                  final value = v?.trim() ?? '';
                  return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$')
                          .hasMatch(value)
                      ? null
                      : 'Email invalide.';
                },
              ),
              const SizedBox(height: Space.lg),
              DropdownButtonFormField<UserRole>(
                initialValue: _role,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Rôle'),
                items: [
                  for (final r in UserRole.values)
                    DropdownMenuItem(
                      value: r,
                      child: Text(r.label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (r) => setState(() => _role = r ?? _role),
              ),
              if (_error != null) ...[
                const SizedBox(height: Space.md),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(color: context.colors.danger),
                  ),
                ),
              ],
              const SizedBox(height: Space.xl),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Text('Créer le compte'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CredentialsDialog extends StatefulWidget {
  const _CredentialsDialog({required this.created, this.title = 'Compte créé'});
  final CreatedMember created;
  final String title;

  @override
  State<_CredentialsDialog> createState() => _CredentialsDialogState();
}

class _CredentialsDialogState extends State<_CredentialsDialog> {
  bool _copied = false;

  String get _message =>
      'Radio Flow\nEmail : ${widget.created.email}\nMot de passe provisoire : ${widget.created.tempPassword}\n'
      'Changez-le dès votre première connexion (Mon compte).';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Transmettez ces identifiants au membre de manière privée. Le mot de passe n’est affiché qu’une seule fois.',
            ),
            const SizedBox(height: Space.lg),
            Text('Email', style: Theme.of(context).textTheme.bodySmall),
            SelectableText(widget.created.email),
            const SizedBox(height: Space.md),
            Text(
              'Mot de passe provisoire',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SelectableText(
              widget.created.tempPassword,
              style: const TextStyle(fontFamily: 'FiraCode', fontSize: 18),
            ),
            if (_copied) ...[
              const SizedBox(height: Space.md),
              Semantics(
                liveRegion: true,
                child: IconLabel(
                  icon: Icons.check_circle_outline,
                  label: 'Copié dans le presse-papiers',
                  color: c.success,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy),
          label: const Text('Copier'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: _message));
            if (mounted) setState(() => _copied = true);
          },
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Terminé'),
        ),
      ],
    );
  }
}
