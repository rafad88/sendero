/// Environment configuration.
/// Values are injected via --dart-define at build time:
///   flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=eyJ...
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

  /// OSM raster tiles — same source used for online viewing and offline download.
  static const tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
}
