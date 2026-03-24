class AppConfig {
  const AppConfig._();

  static const defaultSupabaseUrl =
      'https://mmlwgebgzbdsuhvzbloa.supabase.co';
  static const defaultSupabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1tbHdnZWJnemJkc3VodnpibG9hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMyOTI0MjEsImV4cCI6MjA4ODg2ODQyMX0.kiA0MrjLTn8RZqxaDOvFbcbLTSCVuzpdA2g_HDwApuc';

  static const branchCode =
      String.fromEnvironment('BRANCH_CODE', defaultValue: 'branch1');
  static const branchName =
      String.fromEnvironment('BRANCH_NAME', defaultValue: '\u0031\ud638\uc810');
  static const appTitle =
      String.fromEnvironment('APP_TITLE', defaultValue: 'The Thai');
  static const contactPrefix = String.fromEnvironment(
    'CONTACT_PREFIX',
    defaultValue: branchCode == 'branch2' ? '\ubbf8\uc778' : '\uac15\uc11c',
  );
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: defaultSupabaseUrl,
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: defaultSupabaseAnonKey,
  );

  static void validate() {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw StateError(
        'SUPABASE_URL and SUPABASE_ANON_KEY must not be empty.',
      );
    }
  }
}
