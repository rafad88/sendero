/// Environment configuration.
/// Values are injected via --dart-define at build time:
///   flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=eyJ... \
///               --dart-define=THUNDERFOREST_API_KEY=xxx
///
/// For local development, copy .env.example to .env and use a launch config.
class Env {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://your-project.supabase.co',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'your-anon-key',
  );

  static const thunderforestApiKey = String.fromEnvironment(
    'THUNDERFOREST_API_KEY',
    defaultValue: '',
  );

  /// Thunderforest Landscape when API key is set, OSM standard otherwise.
  static String get tileUrl => thunderforestApiKey.isNotEmpty
      ? 'https://tile.thunderforest.com/landscape/{z}/{x}/{y}.png?apikey=$thunderforestApiKey'
      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
}
