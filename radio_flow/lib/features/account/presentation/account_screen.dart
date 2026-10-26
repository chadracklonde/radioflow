import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/local/local_store.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/data/profile_repository.dart';
import '../../notifications/data/push_service.dart';

/// Profil de l'utilisateur, changement de mot de passe et déconnexion.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mon compte')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(Space.lg),
              children: [
                ...profile.when(
                  loading: () => const [
                    Padding(
                      padding: EdgeInsets.all(Space.xl),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ],
                  error: (_, _) => [const _ProfileUnavailable()],
                  data: (p) => p == null
                      ? [const _ProfileUnavailable()]
                      : [
                          _ProfileCard(profile: p),
                          if (p.isSuperAdmin) ...[
                            const SizedBox(height: Space.md),
                            Card(
                              child: ListTile(
                                leading: const Icon(Icons.groups_outlined),
                                title: const Text('Gérer l\u2019équipe'),
                                subtitle: const Text(
                                  'Ajouter des membres, changer les rôles',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => context.push('/team'),
                              ),
                            ),
                          ],
                          const SizedBox(height: Space.xl),
                          _PasswordForm(email: p.email),
                        ],
                ),
                const SizedBox(height: Space.xl),
                // Toujours disponible, même si le profil ne se charge pas (hors ligne).
                const _SignOutButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileUnavailable extends ConsumerWidget {
  const _ProfileUnavailable();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Row(
          children: [
            Icon(Icons.cloud_off, color: c.mutedForeground),
            const SizedBox(width: Space.md),
            const Expanded(child: Text('Profil indisponible pour le moment.')),
            TextButton(
              onPressed: () => ref.invalidate(profileProvider),
              child: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile});
  final Profile profile;

  String get _initials {
    final parts = profile.fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((x) => x.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    final first = parts.first[0];
    final last = parts.length > 1 ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Row(
          children: [
            ExcludeSemantics(
              child: CircleAvatar(
                radius: 28,
                backgroundColor: c.muted,
                child: Text(
                  _initials,
                  style: text.titleMedium?.copyWith(color: c.success),
                ),
              ),
            ),
            const SizedBox(width: Space.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(profile.fullName, style: text.titleMedium),
                  if (profile.email.isNotEmpty)
                    Text(profile.email, style: text.bodySmall),
                  const SizedBox(height: Space.xs),
                  Text(
                    profile.isSuperAdmin
                        ? 'Super administrateur'
                        : profile.role.label,
                    style: text.bodySmall?.copyWith(
                      color: c.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PasswordForm extends ConsumerStatefulWidget {
  const _PasswordForm({required this.email});
  final String email;

  @override
  ConsumerState<_PasswordForm> createState() => _PasswordFormState();
}

class _PasswordFormState extends ConsumerState<_PasswordForm> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _hidden = true;
  bool _busy = false;
  String? _error;
  bool _done = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _done = false;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .changePassword(
            email: widget.email,
            current: _current.text,
            next: _next.text,
          );
      if (!mounted) return;
      _current.clear();
      _next.clear();
      _confirm.clear();
      setState(() => _done = true);
    } catch (e) {
      if (mounted) setState(() => _error = passwordChangeErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final toggle = IconButton(
      tooltip: _hidden
          ? 'Afficher les mots de passe'
          : 'Masquer les mots de passe',
      icon: Icon(
        _hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
      ),
      onPressed: () => setState(() => _hidden = !_hidden),
    );
    return Form(
      key: _formKey,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Changer le mot de passe',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: Space.lg),
            TextFormField(
              controller: _current,
              obscureText: _hidden,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Mot de passe actuel',
              ),
              validator: (v) => (v == null || v.isEmpty)
                  ? 'Saisissez votre mot de passe actuel.'
                  : null,
            ),
            const SizedBox(height: Space.lg),
            TextFormField(
              controller: _next,
              obscureText: _hidden,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Nouveau mot de passe',
                helperText: 'Au moins 10 caractères, avec lettres et chiffres.',
                suffixIcon: toggle,
              ),
              validator: (v) =>
                  validateNewPassword(v ?? '', current: _current.text),
            ),
            const SizedBox(height: Space.lg),
            TextFormField(
              controller: _confirm,
              obscureText: _hidden,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Confirmer le nouveau mot de passe',
              ),
              validator: (v) => v == _next.text
                  ? null
                  : 'Les deux mots de passe ne correspondent pas.',
            ),
            if (_error != null) ...[
              const SizedBox(height: Space.lg),
              Semantics(
                liveRegion: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, color: c.danger, size: 20),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Text(_error!, style: TextStyle(color: c.danger)),
                    ),
                  ],
                ),
              ),
            ],
            if (_done) ...[
              const SizedBox(height: Space.lg),
              Semantics(
                liveRegion: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      color: c.success,
                      size: 20,
                    ),
                    const SizedBox(width: Space.sm),
                    const Expanded(child: Text('Mot de passe modifié.')),
                  ],
                ),
              ),
            ],
            const SizedBox(height: Space.lg),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Text('Modifier le mot de passe'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignOutButton extends ConsumerWidget {
  const _SignOutButton();

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    // Lecture directe de la file locale : le fournisseur d'état est mis en pause
    // tant que l'écran qui l'observe est masqué par cette page.
    final items = await ref.read(localStoreProvider).items();
    final pending = items.where((i) => !i.failed).length;
    if (!context.mounted) return;
    if (pending > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Modifications non envoyées'),
          content: Text(
            '$pending modification${pending > 1 ? 's' : ''} n’ont pas encore été envoyée${pending > 1 ? 's' : ''} au serveur. '
            'Elles sont conservées sur cet appareil et partiront quand ce compte se reconnectera avec du réseau.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Rester connecté'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Se déconnecter'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    // Retire l'appareil du compte tant que la session est encore valide.
    // (La déconnexion ne dépend jamais des notifications : toute erreur est ignorée.)
    try {
      await ref.read(pushServiceProvider).unregister();
    } catch (_) {}
    await ref.read(authRepositoryProvider).signOut();
    await ref.read(localStoreProvider).clearCache();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlinedButton.icon(
      onPressed: () => _signOut(context, ref),
      icon: const Icon(Icons.logout),
      label: const Text('Se déconnecter'),
    );
  }
}
