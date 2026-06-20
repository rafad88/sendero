# Sendero — Technical Stack & Architecture Decisions

**Version:** 0.1
**Date:** 2026-06-20

---

## 1. Stack Overview

```
┌─────────────────────────────────────────────────────────┐
│                     Mobile App                          │
│              Flutter (iOS + Android)                    │
│                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  MapLibre GL │  │  Local SQLite│  │  GPS Service │  │
│  │  (map render)│  │  (offline DB)│  │  (background)│  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
└────────────────────────┬────────────────────────────────┘
                         │ HTTPS / WebSocket (when online)
┌────────────────────────▼────────────────────────────────┐
│                     Backend                             │
│                  Supabase (cloud)                       │
│                                                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐ ┌─────────┐  │
│  │ Postgres │  │   Auth   │  │ Storage  │ │Realtime │  │
│  │ (routes) │  │ (OAuth)  │  │ (photos) │ │  (sync) │  │
│  └──────────┘  └──────────┘  └──────────┘ └─────────┘  │
└─────────────────────────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────┐
│                  Map Infrastructure                     │
│                                                         │
│  OpenFreeMap (tiles)  │  SRTM (elevation)               │
│  Photon (geocoding)   │  OSRM (routing)                 │
└─────────────────────────────────────────────────────────┘
```

---

## 2. Mobile: Flutter

### Why Flutter over React Native

| Criterion | Flutter | React Native |
|---|---|---|
| Map rendering performance | Native via C++ MapLibre plugin | JS bridge adds latency |
| Offline tile store integration | Direct SQLite access, no bridge | Requires native modules |
| Background GPS | Well-supported via platform channels | More complex, more bugs |
| Single codebase | Yes (Dart) | Yes (JS/TS) |
| UI consistency | Pixel-perfect across platforms | Platform-dependent components |
| Dev ecosystem maturity | Strong, Google-backed | Strong, Meta-backed |

**Decision: Flutter.** The map rendering pipeline and offline tile handling are critical paths. Eliminating the JS bridge for these operations is worth the Dart learning curve.

### Minimum OS Targets
- Android 6.0 (API 23) — covers 97%+ of active Android devices
- iOS 14.0 — covers 96%+ of active iOS devices

---

## 3. Map Rendering: MapLibre GL

MapLibre GL Native is the open-source fork of Mapbox GL Native, maintained by the Linux Foundation.

**Why MapLibre:**
- Fully open source (BSD license), no usage limits, no API key cost
- Renders vector tiles at 60fps natively on both platforms
- Built-in offline tile pack management (download, store, render without network)
- Supports custom styles (JSON style spec compatible with Mapbox styles)
- Active community, funded by multiple organizations

**Flutter integration:** `maplibre_gl` package (community-maintained, production-ready)

### Tile Format Decision: PMTiles over MBTiles

PMTiles is a newer single-file tile archive format optimized for random access.

| | MBTiles | PMTiles |
|---|---|---|
| Format | SQLite database | Flat binary with spatial index |
| Random access | B-tree lookup (SQLite overhead) | Direct byte-range offset |
| HTTP Range requests | Not supported | Native (stream from CDN) |
| Mobile local storage | Good | Better (no SQLite locking) |
| Tooling maturity | Mature | Growing rapidly |

**Decision: PMTiles** for region downloads. The byte-range access pattern means a single .pmtiles file per region can be served from a CDN and accessed locally without SQLite overhead.

---

## 4. Offline Architecture

### Tile Download Flow

```
User selects region on map
        │
        ▼
Calculate bounding box + zoom levels 0–16
        │
        ▼
Estimate download size (shown to user)
        │
[User confirms]
        │
        ▼
Download .pmtiles from OpenFreeMap CDN
        │
        ▼
Store in app documents directory
        │
        ▼
Register in local OfflinePackage table
        │
        ▼
MapLibre reads tiles directly from local .pmtiles
```

### Storage Budget
- Zoom 0–10: regional context (~2 MB per 10,000 km²)
- Zoom 11–14: trail-level detail (~15 MB per 100 km²)
- Zoom 15–16: street/path detail (~40 MB per 100 km²)
- Typical day-hike area (25 km²): ~8–12 MB
- Full Pyrenees range: ~180 MB

### Elevation Data (offline)
- Source: SRTM 1-arc-second (30m resolution), public domain
- Pre-processed into terrain tiles (Terrarium encoding)
- Bundled with the same .pmtiles download
- Used for: hillshading, contour lines, elevation profile, grade calculation

---

## 5. GPS Tracking Engine

### Background Location Strategy

Flutter's `geolocator` package provides cross-platform location access. For background tracking:

- **Android:** Foreground Service with persistent notification (required by OS)
- **iOS:** `allowsBackgroundLocationUpdates = true` + significant location change monitoring as fallback

### Accuracy Modes

```dart
enum TrackingMode {
  precision,  // 1s interval, best accuracy, ~15% battery/hr
  standard,   // 5s interval, high accuracy, ~8% battery/hr  (default)
  eco,        // 15s interval, balanced accuracy, ~3% battery/hr
}
```

### Track Point Storage

Points stored in local SQLite immediately (no buffer loss on crash):

```sql
CREATE TABLE track_points (
  id          INTEGER PRIMARY KEY,
  track_id    TEXT NOT NULL,
  lat         REAL NOT NULL,
  lon         REAL NOT NULL,
  ele         REAL,          -- meters, from GPS or SRTM
  accuracy    REAL,          -- meters
  speed       REAL,          -- m/s
  bearing     REAL,          -- degrees
  recorded_at INTEGER NOT NULL  -- Unix timestamp ms
);
```

Points are compressed before sync using Douglas-Peucker simplification (epsilon = 5m for cloud copy; full resolution kept locally).

### Off-Route Detection (offline)

```
Every 10 seconds:
  current_point = latest GPS fix
  nearest_point = closest point on downloaded route LineString
  distance = haversine(current_point, nearest_point)
  
  if distance > threshold (default: 50m):
    trigger off-route alert (haptic + audio)
```

Implemented in Dart using the local route geometry — zero network dependency.

---

## 6. Local Database: Drift (SQLite)

**Drift** (formerly Moor) is a type-safe SQLite ORM for Flutter.

### Why Drift over alternatives
- Type-safe queries (compile-time verified, unlike raw sqflite)
- Reactive streams (UI rebuilds automatically when data changes)
- Migration support (versioned schema upgrades)
- Works in background isolates (important for GPS recording)

### Schema summary

```dart
// Core tables
class Users extends Table { ... }
class Routes extends Table { ... }
class RouteWaypoints extends Table { ... }
class Tracks extends Table { ... }         // activity recordings
class TrackPoints extends Table { ... }    // raw GPS stream
class OfflinePackages extends Table { ... } // downloaded map regions
class SyncQueue extends Table { ... }       // pending cloud sync operations
```

---

## 7. Backend: Supabase

### Why Supabase
- Postgres at the core (PostGIS extension for geospatial queries)
- Auth (email + OAuth) out of the box
- Row-Level Security (RLS) for multi-tenant data isolation
- Realtime subscriptions (needed for live location sharing)
- Storage for photos and GPX exports
- Edge Functions for server-side processing
- Self-hostable when cloud costs grow

### Key Postgres Extensions
- `postgis` — spatial indexing, distance queries, geometry operations
- `pg_trgm` — fuzzy text search for route names
- `uuid-ossp` — UUID primary keys

### Row-Level Security Examples

```sql
-- Users can only read their own private routes
CREATE POLICY "private routes" ON routes
  FOR SELECT USING (
    is_public = true OR author_id = auth.uid()
  );

-- Only route author can update
CREATE POLICY "author update" ON routes
  FOR UPDATE USING (author_id = auth.uid());
```

### Sync Strategy

**Optimistic local-first sync:**

1. All writes go to local SQLite immediately → UI updates instantly
2. Write is added to `sync_queue` table with operation type (INSERT/UPDATE/DELETE)
3. `SyncService` runs when network is available, processes queue in order
4. On conflict (same entity modified on two devices): last-write-wins by `updated_at`
5. Failed sync operations retry with exponential backoff (max 7 days)

```dart
class SyncService {
  Future<void> flush() async {
    final pending = await db.syncQueue.getPending();
    for (final op in pending) {
      try {
        await supabase.rpc(op.procedure, params: op.payload);
        await db.syncQueue.markSynced(op.id);
      } on PostgrestException catch (e) {
        await db.syncQueue.recordFailure(op.id, e.message);
      }
    }
  }
}
```

---

## 8. Map Data Sources

### Base Map: OpenFreeMap
- URL: `https://tiles.openfreemap.org/`
- License: ODbL (OpenStreetMap data)
- Format: PMTiles vector tiles
- Update frequency: Weekly OSM diff applied
- Cost: Free, infrastructure maintained by community donations
- Fallback: Self-host from OSM planet file using tilemaker

### Elevation: OpenTopoData (SRTM)
- Used only during region download pre-processing
- SRTM 1 arc-second (30m resolution, global coverage)
- Processed offline into Terrarium-encoded terrain tiles
- Stored in same .pmtiles bundle as base tiles

### Geocoding: Photon
- Open-source geocoder built on OpenStreetMap data
- Self-hosted on Supabase Edge or a small VPS
- No usage limits, no API key
- Used for: search bar, reverse geocoding of saved tracks

### Routing: OSRM (foot + bicycle profiles)
- For: navigate-to-trailhead directions, snap-to-trail during recording
- Self-hosted; lightweight for foot/bike profiles
- Pre-computed graphs for priority regions bundled with app

---

## 9. CI/CD Pipeline

```
GitHub Actions
    │
    ├── PR checks
    │     ├── flutter test (unit + integration)
    │     ├── flutter analyze (linter)
    │     └── dart format --check
    │
    ├── Main branch → staging
    │     ├── Build Android APK + iOS ipa
    │     ├── Deploy to Firebase App Distribution (internal testers)
    │     └── Run Supabase migrations on staging DB
    │
    └── Release tag → production
          ├── Build signed Android AAB
          ├── Build signed iOS ipa
          ├── Upload to Play Store (internal track) + App Store Connect
          └── Run Supabase migrations on production DB
```

---

## 10. Security Considerations

| Concern | Approach |
|---|---|
| Location data privacy | Stored encrypted at rest (Supabase + device encryption); never sold |
| API key exposure | No sensitive keys in app bundle; all auth via Supabase JWT |
| GPX imports | Parse in isolate; validate bounds before rendering; no executable content |
| GDPR compliance | Data export endpoint; account deletion removes all PII; EU Supabase region |
| Background location consent | Explicit OS permission dialog; clear explanation of why it's needed |
| Offline data on shared devices | Option to lock app with device biometrics |

---

## 11. Architecture Decision Records (ADRs)

### ADR-001: Flutter over React Native
**Status:** Accepted
**Decision:** Use Flutter as the mobile framework
**Reason:** Superior map rendering performance via native C++ MapLibre plugin, no JS bridge overhead for GPS-intensive operations

### ADR-002: PMTiles over MBTiles
**Status:** Accepted
**Decision:** Use PMTiles format for offline map storage
**Reason:** Better random-access performance, no SQLite locking issues in background, future CDN byte-range serving option

### ADR-003: Supabase over custom backend
**Status:** Accepted
**Decision:** Use Supabase as the backend platform
**Reason:** PostGIS support, built-in auth, generous free tier, self-hostable exit ramp; avoids building auth/storage infrastructure from scratch

### ADR-004: Local-first sync
**Status:** Accepted
**Decision:** All writes go to local DB first, sync to cloud asynchronously
**Reason:** Core value proposition requires full functionality without network; last-write-wins acceptable for solo-user data

### ADR-005: OpenFreeMap over Mapbox/Google Maps
**Status:** Accepted
**Decision:** Use OpenFreeMap as the tile source
**Reason:** Zero per-tile cost (critical for offline-heavy usage patterns), OSM data quality sufficient for outdoor trails, avoids vendor lock-in

---

*Related: [PRD.md](PRD.md) — product requirements*
*Related: [USER_FLOWS.md](USER_FLOWS.md) — user journeys*
