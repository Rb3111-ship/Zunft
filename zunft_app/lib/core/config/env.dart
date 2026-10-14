/// Build-time configuration, passed with --dart-define (see README).
///
///   flutter run --dart-define=SUPABASE_URL=http://10.0.2.2:54321 \
///               --dart-define=SUPABASE_ANON_KEY=<anon key>
///
/// Only the public anon key belongs here. Never put the service-role key,
/// GEMINI_API_KEY or DEEPGRAM_API_KEY in the app.
class Env {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Where the owner pays or renews (the website's subscription page, later a Stripe link).
  /// Empty until it exists: the app then says so.
  static const String billingUrl = String.fromEnvironment('BILLING_URL');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
