/// Configuration Supabase. Surchargeable avec --dart-define=SUPABASE_URL=... et
/// --dart-define=SUPABASE_PUBLISHABLE_KEY=... (la clé publique est faite pour être embarquée).
abstract final class SupabaseConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://yjzzgduvoirjvhfjfszz.supabase.co',
  );
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_8o6zi54UEWrQPJ7l7YNzKA_fWU0AVNX',
  );
}
