import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_repository.dart';

enum UserRole {
  admin,
  journalist,
  technician;

  static UserRole parse(String? v) => UserRole.values.firstWhere(
    (r) => r.name == v,
    orElse: () => UserRole.technician,
  );

  String get label => switch (this) {
    UserRole.admin => 'Rédacteur en chef',
    UserRole.journalist => 'Journaliste',
    UserRole.technician => 'Technicien / Présentateur',
  };
}

class Profile {
  const Profile({
    required this.id,
    required this.fullName,
    required this.role,
    this.email = '',
    this.isSuperAdmin = false,
    this.deputyUntil,
  });
  final String id;
  final String fullName;
  final UserRole role;
  final String email;

  /// Seul compte autorisé à créer des membres et à attribuer des rôles.
  final bool isSuperAdmin;

  /// Fin de la suppléance en cours : le rôle est alors celui de rédacteur en chef.
  final DateTime? deputyUntil;

  bool get isDeputy => deputyUntil != null;

  bool get isAdmin => role == UserRole.admin;
  bool get canPropose => role == UserRole.admin || role == UserRole.journalist;

  /// Tous les rôles peuvent envoyer des sons (techniciens compris).
  bool get canSendAudio => true;

  /// Texte à lire à l'antenne : rédacteur en chef et journalistes.
  bool get canWriteScript => canPropose;
}

abstract class ProfileRepository {
  Future<Profile?> fetchMe();

  /// Noms complets par identifiant (pour afficher les auteurs).
  Future<Map<String, String>> fetchNames();
}

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<Profile?> fetchMe() async {
    final id = _client.auth.currentUser?.id;
    if (id == null) return null;
    final row = await _client
        .from('users')
        .select('id, full_name, role, email, is_super_admin, deputy_until')
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    final deputyUntil = DateTime.tryParse(
      (row['deputy_until'] as String?) ?? '',
    )?.toLocal();
    final deputyActive =
        deputyUntil != null && deputyUntil.isAfter(DateTime.now());
    final baseRole = UserRole.parse(row['role'] as String?);
    return Profile(
      id: row['id'] as String,
      fullName: row['full_name'] as String,
      deputyUntil: deputyActive ? deputyUntil : null,
      role: deputyActive ? UserRole.admin : baseRole,
      email: (row['email'] as String?) ?? '',
      isSuperAdmin: (row['is_super_admin'] as bool?) ?? false,
    );
  }

  @override
  Future<Map<String, String>> fetchNames() async {
    final rows = await _client.from('users').select('id, full_name');
    return {for (final r in rows) r['id'] as String: r['full_name'] as String};
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => SupabaseProfileRepository(Supabase.instance.client),
);

/// Profil de l'utilisateur connecté; se recharge à chaque changement de session.
final profileProvider = FutureProvider<Profile?>((ref) async {
  final signedIn = ref.watch(signedInProvider).value ?? false;
  if (!signedIn) return null;
  return ref.watch(profileRepositoryProvider).fetchMe();
});

final authorNamesProvider = FutureProvider<Map<String, String>>((ref) async {
  final signedIn = ref.watch(signedInProvider).value ?? false;
  if (!signedIn) return const {};
  return ref.watch(profileRepositoryProvider).fetchNames();
});
