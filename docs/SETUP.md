# Sendero — Setup Guide

## 1. Install Flutter

```powershell
# Option A: winget (recommended)
winget install Google.Flutter

# Option B: manual
# Download from https://docs.flutter.dev/get-started/install/windows
# Extract to C:\flutter
# Add C:\flutter\bin to PATH
```

Verify install:
```powershell
flutter doctor
```

All checks must pass (Android toolchain + Chrome for web, or Android Studio/Xcode for device).

---

## 2. Install dependencies

```powershell
cd D:\Git\trail-app
flutter pub get
```

---

## 3. Run code generation (required before first run)

Drift (database), Riverpod, and Freezed all require generated files (`*.g.dart`).

```powershell
# One-time generation
flutter pub run build_runner build --delete-conflicting-outputs

# Watch mode during development (auto-regenerates on save)
flutter pub run build_runner watch --delete-conflicting-outputs
```

---

## 4. Set up Supabase

1. Create a free project at https://supabase.com
2. Go to **Project Settings → API** and copy:
   - `Project URL`
   - `anon public` key
3. Run the schema migrations (in `docs/architecture/DATA_SCHEMA.md`, section 3)
   - Open the Supabase SQL Editor
   - Paste and run the Postgres schema block by block
4. Set environment variables:

```powershell
$env:SUPABASE_URL = "https://your-project.supabase.co"
$env:SUPABASE_ANON_KEY = "eyJhbGciOi..."
```

Or create `.env.local` and use the VS Code launch config (`.vscode/launch.json` is pre-configured).

---

## 5. Run the app

```powershell
# Android emulator or connected device
flutter run --dart-define=SUPABASE_URL=$env:SUPABASE_URL `
            --dart-define=SUPABASE_ANON_KEY=$env:SUPABASE_ANON_KEY

# iOS simulator (macOS only)
flutter run -d ios ...

# Chrome (limited — GPS and background tracking not available)
flutter run -d chrome ...
```

---

## 6. Android permissions (already configured)

The following are declared in `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

---

## 7. iOS permissions (Info.plist)

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Sendero uses your location to track your route.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Sendero needs background location to record your activity when the screen is off.</string>
<key>UIBackgroundModes</key>
<array>
  <string>location</string>
  <string>fetch</string>
</array>
```

---

## 8. Project structure

```
lib/
├── main.dart
├── core/
│   ├── config/         env.dart (dart-define vars)
│   ├── database/       Drift schema + app_database.dart
│   │   └── tables/     one file per table
│   ├── router/         GoRouter setup
│   ├── sync/           SyncService
│   ├── theme/          AppTheme + AppColors
│   └── widgets/        MainShell (bottom nav)
│
└── features/
    ├── auth/
    │   ├── presentation/   onboarding_screen, login_screen
    │   └── providers/      auth_provider.dart
    ├── map/
    │   └── presentation/   map_screen.dart
    ├── tracking/
    │   ├── presentation/   tracking_screen, save_activity_screen
    │   └── providers/      tracking_provider.dart
    ├── routes/
    │   └── presentation/   explore_screen, route_detail_screen
    ├── profile/
    │   └── presentation/   profile_screen.dart
    └── offline/
        └── presentation/   offline_maps_screen.dart
```

---

## 9. Common development commands

```powershell
# Run tests
flutter test

# Analyze code
flutter analyze

# Check for outdated packages
flutter pub outdated

# Build release APK
flutter build apk --release `
  --dart-define=SUPABASE_URL=$env:SUPABASE_URL `
  --dart-define=SUPABASE_ANON_KEY=$env:SUPABASE_ANON_KEY

# Build release App Bundle (Play Store)
flutter build appbundle --release ...

# Build iOS (macOS only)
flutter build ios --release ...
```
