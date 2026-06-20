# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# MapLibre
-keep class com.mapbox.** { *; }
-keep class com.maplibre.** { *; }

# Supabase / OkHttp
-dontwarn okhttp3.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }

# SQLite / Drift
-keep class org.sqlite.** { *; }
-keep class org.sqlite.database.** { *; }
