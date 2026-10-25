import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/data/profile_repository.dart';

class TeamMember {
  const TeamMember({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.active,
    this.isSuperAdmin = false,
  });

  final String id;
  final String fullName;
  final String email;
  final UserRole role;
  final bool active;
  final bool isSuperAdmin;

  factory TeamMember.fromJson(Map<String, dynamic> j) => TeamMember(
    id: j['id'] as String,
    fullName: j['full_name'] as String,
    email: j['email'] as String,
    role: UserRole.parse(j['role'] as String?),
    active: (j['active'] as bool?) ?? true,
    isSuperAdmin: (j['is_super_admin'] as bool?) ?? false,
  );
}

/// Compte créé : le mot de passe provisoire n'est renvoyé qu'une seule fois.
class CreatedMember {
  const CreatedMember({
    required this.id,
    required this.email,
    required this.tempPassword,
  });
  final String id;
  final String email;
  final String tempPassword;
}

/// Erreur lisible renvoyée par le serveur (déjà en français).
class TeamException implements Exception {
  const TeamException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract class TeamRepository {
  Future<List<TeamMember>> fetch();
  Future<void> setRole(String id, UserRole role);
  Future<CreatedMember> create({
    required String email,
    required String fullName,
    required UserRole role,
  });
  Future<void> setActive(String id, bool active);
}

class SupabaseTeamRepository implements TeamRepository {
  SupabaseTeamRepository(this._client);
  final SupabaseClient _client;

  static const _function = 'manage-team';

  @override
  Future<List<TeamMember>> fetch() async {
    final rows = await _client
        .from('users')
        .select('id, full_name, email, role, active, is_super_admin')
        .order('full_name');
    return rows.map(TeamMember.fromJson).toList();
  }

  @override
  Future<void> setRole(String id, UserRole role) async {
    try {
      await _client.from('users').update({'role': role.name}).eq('id', id);
    } on PostgrestException catch (e) {
      // Les garde-fous de la base (dernier administrateur...) renvoient un message en français.
      throw TeamException(e.message);
    }
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    try {
      final res = await _client.functions.invoke(_function, body: body);
      return Map<String, dynamic>.from(res.data as Map);
    } on FunctionException catch (e) {
      final details = e.details;
      final message = details is Map && details['error'] is String
          ? details['error'] as String
          : 'Action impossible. Réessayez.';
      throw TeamException(message);
    }
  }

  @override
  Future<CreatedMember> create({
    required String email,
    required String fullName,
    required UserRole role,
  }) async {
    final d = await _invoke({
      'action': 'create',
      'email': email.trim(),
      'full_name': fullName.trim(),
      'role': role.name,
    });
    return CreatedMember(
      id: d['id'] as String,
      email: d['email'] as String,
      tempPassword: d['temp_password'] as String,
    );
  }

  @override
  Future<void> setActive(String id, bool active) async {
    await _invoke({'action': active ? 'reactivate' : 'deactivate', 'id': id});
  }
}

final teamRepositoryProvider = Provider<TeamRepository>(
  (ref) => SupabaseTeamRepository(Supabase.instance.client),
);

final teamProvider = FutureProvider.autoDispose<List<TeamMember>>(
  (ref) => ref.watch(teamRepositoryProvider).fetch(),
);
