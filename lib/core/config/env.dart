/// Environment configuration.
/// Values are injected via --dart-define at build time:
///   flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=eyJ... \
///               --dart-define=STADIA_API_KEY=xxx
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

  static const stadiaApiKey = String.fromEnvironment(
    'STADIA_API_KEY',
    defaultValue: '',
  );

  /// Tile URL: Stadia Alidade Outdoor when API key is set, OpenTopoMap otherwise.
  static String get tileUrl => stadiaApiKey.isNotEmpty
      ? 'https://tiles.stadiamaps.com/tiles/outdoors/{z}/{x}/{y}@2x.png?api_key=$stadiaApiKey'
      : 'https://tile.opentopomap.org/{z}/{x}/{y}.png';
}
