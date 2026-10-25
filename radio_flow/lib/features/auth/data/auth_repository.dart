import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Accès à l'authentification Supabase, isolé pour pouvoir le remplacer dans les tests.
abstract class AuthRepository {
  /// Émet `true` quand une session est ouverte, `false` sinon.
  Stream<bool> signedIn();
  Future<void> signIn({required String email, required String password});
  Future<void> signOut();

  /// Vérifie le mot de passe actuel puis le remplace.
  Future<void> changePassword({
    required String email,
    required String current,
    required String next,
  });
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._auth);
  final GoTrueClient _auth;

  @override
  Stream<bool> signedIn() async* {
    yield _auth.currentSession != null;
    yield* _auth.onAuthStateChange.map((e) => e.session != null);
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    await _auth.signInWithPassword(email: email.trim(), password: password);
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> changePassword({
    required String email,
    required String current,
    required String next,
  }) async {
    // Reconnexion avec le mot de passe actuel : prouve que c'est bien le titulaire du compte.
    await _auth.signInWithPassword(email: email.trim(), password: current);
    await _auth.updateUser(UserAttributes(password: next));
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => SupabaseAuthRepository(Supabase.instance.client.auth),
);

final signedInProvider = StreamProvider<bool>(
  (ref) => ref.watch(authRepositoryProvider).signedIn(),
);

/// Message d'erreur lisible en français pour l'écran de connexion.
String authErrorMessage(Object error) {
  if (error is AuthException) {
    final m = error.message.toLowerCase();
    if (m.contains('invalid login credentials')) {
      return 'Email ou mot de passe incorrect.';
    }
    if (m.contains('banned') || error.code == 'user_banned') {
      return 'Ce compte a été désactivé. Contactez le rédacteur en chef.';
    }
    if (m.contains('email not confirmed')) {
      return 'Confirmez votre email avant de vous connecter.';
    }
    if (m.contains('rate limit') || error.statusCode == '429') {
      return 'Trop de tentatives. Réessayez dans quelques minutes.';
    }
    return error.message;
  }
  return 'Connexion impossible. Vérifiez votre réseau et réessayez.';
}

/// Message lisible pour le changement de mot de passe.
String passwordChangeErrorMessage(Object error) {
  if (error is AuthException) {
    final m = error.message.toLowerCase();
    if (m.contains('invalid login credentials')) {
      return 'Mot de passe actuel incorrect.';
    }
    if (m.contains('different from the old')) {
      return 'Le nouveau mot de passe doit être différent de l\u2019ancien.';
    }
    if (m.contains('at least') || m.contains('weak') || m.contains('pwned')) {
      return 'Mot de passe trop faible ou trop courant. Choisissez-en un autre.';
    }
    if (m.contains('rate limit') || error.statusCode == '429') {
      return 'Trop de tentatives. Réessayez dans quelques minutes.';
    }
    return error.message;
  }
  return 'Changement impossible. Vérifiez votre réseau et réessayez.';
}

/// Règle de robustesse du nouveau mot de passe; renvoie un message ou null.
String? validateNewPassword(String value, {String? current}) {
  if (value.length < 10) return 'Au moins 10 caractères.';
  if (!RegExp(r'[A-Za-z]').hasMatch(value) ||
      !RegExp(r'[0-9]').hasMatch(value)) {
    return 'Mélangez des lettres et des chiffres.';
  }
  if (current != null && value == current) {
    return 'Doit être différent du mot de passe actuel.';
  }
  return null;
}
