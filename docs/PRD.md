# Sendero — Product Requirements Document

**Version:** 0.1 (Inception)
**Date:** 2026-06-20
**Status:** Draft

---

## 1. Vision

> "The outdoor navigation app that works everywhere — even where there's no signal."

Sendero is a free, offline-first trail and route tracking app for hikers, cyclists, trail runners, and outdoor explorers worldwide. It delivers the polished experience of AllTrails with the community depth of Wikiloc, but removes the paywall from the one feature every outdoor user needs most: **offline maps and route tracking**.

---

## 2. Problem Statement

Every major outdoor navigation app forces a choice:

- **Pay for offline** (AllTrails $36/yr, Wikiloc $9.99/yr, Komoot per-region)
- **Get offline for free but suffer a terrible UX** (OsmAnd, Maps.me)
- **Use a great free app that fails the moment you lose signal** (AllTrails free tier)

This is a false dilemma. The technical cost of offline maps has collapsed thanks to open data (OpenStreetMap) and open infrastructure (OpenFreeMap, Protomaps). There is no legitimate reason to charge for offline — it is a pricing strategy, not a cost constraint.

Sendero's bet: **make offline-first the default, not a premium tier**, and build a sustainable business on top of that trust.

---

## 3. Target Users

### Primary: The Weekend Explorer
- Age 25–45, active 1–3 times/week outdoors
- Hikes, bikes, or trail-runs in areas with poor or no mobile coverage
- Price-sensitive; resents paywalls on core features
- Android or iPhone, intermediate tech comfort
- Frustrated that downloaded routes disappear mid-hike when the app requires connectivity

### Secondary: The International Traveler
- Travels to regions where roaming data is expensive or unavailable
- Needs full map and route functionality without a local SIM or Wi-Fi
- Uses the app in preparation at home + fully offline in the field

### Tertiary: The Route Creator
- Creates and publishes GPX tracks for a local community
- Wants analytics, waypoint descriptions, and multi-media attachments
- Willing to pay for advanced creator tools (monetization lever)

---

## 4. Core Principles

1. **Offline is not a feature — it is the baseline.** Every function that can work offline, must work offline.
2. **Free is not a trial.** The free tier is complete for solo exploration. Paid tiers enhance, not unlock.
3. **Sync without thinking.** Data created offline syncs automatically and silently when connectivity returns.
4. **Battery is sacred.** GPS background tracking must consume as little power as possible. Users configure the tradeoff, not us.
5. **Community is the moat.** Routes, photos, and reviews created by users are the irreplaceable asset.
6. **Open data in, open data out.** Import and export GPX/FIT/KML freely. No lock-in.

---

## 5. Feature Set

### 5.1 MVP (v1.0)

#### Offline Maps
- Vector tile maps downloaded by area (bounding box or named region)
- Source: OpenStreetMap via OpenFreeMap / Protomaps (zero tile cost)
- Rendered with MapLibre GL Native (iOS + Android)
- Storage estimate: ~50 MB per 100 km² at full detail
- Hillshading and contour lines from SRTM (public domain elevation data)
- Map style: outdoor-optimized (trail emphasis, elevation tinting)

#### Route Discovery
- Browse and search routes from the Sendero community database
- Filter by: activity type, distance, elevation gain, difficulty, rating
- Route detail page: map preview, stats, photos, user reviews
- Download any route for offline use (map tiles + track + waypoints)
- Import GPX / KML / FIT files from any source

#### Live GPS Tracking
- Start tracking with one tap — no account required
- Background tracking (screen off) with configurable accuracy/battery modes:
  - **Precision** — 1-second intervals, highest accuracy, high battery use
  - **Standard** — 5-second intervals (default)
  - **Eco** — 15-second intervals, minimal battery drain
- On-screen stats: distance, pace, elevation, elapsed time, remaining distance to finish
- Audio cues at configurable distance milestones
- Off-route alert (works fully offline via local comparison against downloaded track)
- Track stored locally immediately; synced to cloud when online

#### Recording & Saving
- Save recorded tracks as private or public routes
- Add title, description, difficulty rating, activity type
- Attach photos taken during the activity (geotagged)
- Export to GPX, FIT, KML at any time
- Automatic activity summary card (shareable image)

#### Elevation Profile
- Generated offline from SRTM data bundled with the map download
- Shows current position on profile during tracking
- Displays grade percentage, uphill/downhill totals

#### Basic User Account
- Sign up with email or OAuth (Google, Apple)
- Profile with activity history and stats
- Followers / following (social graph, no algorithm feed)
- Route library: saved, downloaded, created

### 5.2 Post-MVP (v1.x — v2.0)

| Feature | Notes |
|---|---|
| Turn-by-turn navigation | Voice directions for driving to trailhead + on-trail |
| Offline weather layers | Pre-downloaded forecast tiles for next 24h |
| Heatmaps | Popular segment overlays (anonymized aggregate) |
| Multi-day planning | String routes together with camp spots / POIs |
| Live location sharing | Share real-time location with a group (offline mesh via BLE/WiFi-Direct in v2) |
| Emergency beacon mode | Send last known GPS to emergency contacts via SMS fallback |
| Wearable sync | Wear OS / watchOS companion for glanceable stats |
| AR trailhead finder | Camera overlay showing nearby trails and distance |
| Route collections | Curated lists (e.g. "Best via ferratas in the Alps") |

---

## 6. Technical Architecture

### 6.1 Mobile App

**Framework:** Flutter (Dart)
- Single codebase for iOS and Android
- MapLibre GL Flutter plugin for native-performance map rendering
- Chosen over React Native due to better offline tile handling and smoother 60fps map interaction

**Key packages:**
- `maplibre_gl` — vector tile rendering, offline tile storage
- `geolocator` + `background_fetch` — background GPS acquisition
- `sqflite` / `drift` — local SQLite for routes, tracks, waypoints, user data
- `isar` — fast local object store for app state
- `gpx` — GPX parsing and export
- `supabase_flutter` — sync, auth, storage

**Offline tile pipeline:**
```
OpenFreeMap CDN  →  Pre-packaged .mbtiles by region  →  Local SQLite tile store
                     (downloaded in-app on demand)         (MapLibre reads directly)
```

**Sync architecture:**
```
Local DB (source of truth)
    ↓ delta sync (last_modified timestamp)
Supabase Postgres (when online)
    ↓ broadcast
Other devices / community feed
```

All writes go to local DB first. A sync queue flushes to Supabase when connectivity is detected. Conflict resolution: last-write-wins per entity, with user notification on conflict.

### 6.2 Backend

**Stack:** Supabase (Postgres + Auth + Storage + Realtime)

| Service | Use |
|---|---|
| Postgres | Routes, tracks, waypoints, users, reviews |
| Supabase Auth | Email + OAuth (Google, Apple) |
| Supabase Storage | Photos, GPX file exports |
| Supabase Realtime | Live location sharing (v1.x) |
| Edge Functions (Deno) | Route processing, thumbnail generation, stats aggregation |

**Hosting:** Supabase cloud (generous free tier; self-hostable for cost control at scale)

### 6.3 Map Infrastructure

| Layer | Source | Cost |
|---|---|---|
| Vector base tiles | OpenFreeMap | Free (open infrastructure) |
| Elevation / hillshading | SRTM + OpenTopoData | Free |
| Satellite imagery | Mapbox Satellite (optional overlay) | Pay-per-use (premium tier only) |
| Geocoding (search) | Photon (OSM-based, self-hosted) | Free |
| Routing engine | OSRM or Valhalla (self-hosted) | Free |

### 6.4 Data Model (simplified)

```
User
  ├── id, email, display_name, avatar_url
  ├── settings (JSON: gps_mode, units, language)
  └── stats (total_distance, total_elevation, activity_count)

Route
  ├── id, title, description, author_id
  ├── activity_type (hike|bike|run|ski|...)
  ├── difficulty (1–5)
  ├── distance_m, elevation_gain_m, elevation_loss_m
  ├── geom (LineString, PostGIS)
  ├── waypoints (JSON array)
  ├── is_public, is_deleted
  └── created_at, updated_at

Track (raw recording)
  ├── id, user_id, route_id (nullable)
  ├── started_at, finished_at
  ├── points (compressed binary: lat/lon/ele/time/accuracy)
  ├── distance_m, duration_s
  └── synced_at (null = pending sync)

OfflinePackage
  ├── id, user_id
  ├── bounds (GeoJSON bbox)
  ├── tile_path (local file)
  ├── size_bytes
  └── downloaded_at
```

---

## 7. UX & Design Principles

- **Map-first.** The map is the home screen. No dashboard, no feed, no friction.
- **One-tap tracking.** Record button is always visible. Tap once, it tracks.
- **Progressive disclosure.** Advanced settings are buried. Defaults work for 90% of users.
- **Dark mode native.** Outdoor use under sun glare requires high-contrast dark palette option.
- **Accessible typography.** Large, legible on-trail stats. No tiny numbers.
- **Design system:** Material 3 (Flutter default) customized with an earthy outdoor palette.

### Color Palette
- Primary: `#2D6A4F` (forest green)
- Secondary: `#F4845F` (trail orange)  
- Surface: `#F8F4EF` (parchment) / `#1A1A2E` (dark mode)
- Elevation tint: `#D4A373` → `#6D6875` (low → high)

---

## 8. Monetization Strategy

The free tier is **intentionally complete** for solo use. Monetization targets power users and B2B, not basic functionality.

### Tier 1: Free (permanent)
- Unlimited GPS tracking
- Offline maps (up to 3 downloaded regions)
- Route discovery and download (unlimited)
- GPX import/export
- Community features (publish, review, follow)
- 1 GB photo storage

### Tier 2: Explorer ($3.99/month or $29/year)
- Unlimited offline region downloads
- Advanced stats and training metrics (VO2max estimate, TSS)
- Custom map overlays (IGN, local topo maps)
- 10 GB photo storage
- Satellite imagery overlay
- Priority sync

### Tier 3: Creator ($7.99/month or $59/year)
- Everything in Explorer
- Route analytics (views, downloads, heatmap of user paths)
- Waypoint rich content (video, audio notes)
- Custom branded route collections
- API access for route embed widgets
- Verified creator badge

### B2B: Territory ($199/year per organization)
- For tourism boards, trail associations, national parks
- Official route collections with custom branding
- Analytics dashboard (aggregate, anonymized)
- Embed widget for their website
- White-label option (enterprise)

### Additional revenue streams
- **Gear affiliate links** — contextual recommendations on route pages (e.g., recommended footwear for terrain type)
- **Guided experience marketplace** — local guides list paid experiences; Sendero takes 15% commission
- **Donations / tip jar** — voluntary support for free users who want to contribute

---

## 9. Go-to-Market

### Phase 0 — Seed Content (pre-launch, month 1–2)
- Import publicly licensed GPX routes from OSM, public trail databases
- Seed 50,000+ routes across top outdoor regions (Alps, Pyrenees, Andes, Rockies, Appalachians, NZ)
- Partner with 5–10 trail influencers for beta access and initial reviews

### Phase 1 — Soft Launch (month 3)
- App Store + Google Play release
- Product Hunt launch
- r/hiking, r/trailrunning, r/cycling communities
- Focus: gather reviews, fix critical bugs, optimize battery consumption

### Phase 2 — Community Growth (month 4–8)
- Ambassador program: active route creators get Creator tier free
- Integration with Strava (import activities)
- Press outreach: outdoor magazines, tech blogs (The Verge, iMore)
- SEO: route pages indexed by Google (web companion to the app)

### Phase 3 — Monetization Activation (month 9+)
- Launch Explorer and Creator tiers
- B2B outreach to tourism boards in Spain, France, New Zealand
- Gear affiliate program activation

---

## 10. Success Metrics

### North Star Metric
**Weekly Active Trackers (WAT)** — users who complete at least one tracked activity per week

### Supporting Metrics

| Metric | Target (Month 6) | Target (Month 12) |
|---|---|---|
| Total installs | 50,000 | 200,000 |
| WAT | 8,000 | 35,000 |
| Routes in DB | 100,000 | 500,000 |
| Offline packages downloaded | 15,000 | 80,000 |
| Paid conversion rate | — | 4% |
| App store rating | ≥ 4.4 | ≥ 4.5 |
| D30 retention | 25% | 30% |

---

## 11. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| AllTrails launches free offline | Medium | High | Community and local content are the moat; respond with social features |
| OpenFreeMap infrastructure instability | Low | High | Self-host fallback tile server; cache aggressively |
| App Store rejection (background GPS) | Low | Medium | Follow Apple guidelines strictly; clear user consent flows |
| Low content density in niche regions | High | Medium | Enable easy GPX import; reward early contributors with Creator tier |
| Background GPS drains battery | High | Medium | Eco mode default; transparent battery % estimate before tracking |
| GDPR / location data compliance | Medium | High | Data minimization; on-device processing; clear privacy policy from day 1 |

---

## 12. Open Questions

- [ ] App name trademark check: "Sendero" in target markets
- [ ] Self-host Supabase from day 1 or use cloud until 10k users?
- [ ] Offline tile format: .mbtiles vs. PMTiles (PMTiles has better random-access performance)
- [ ] GPX import from Wikiloc: scraping vs. user-initiated export (legal/TOS risk)
- [ ] Minimum viable web companion (for SEO / route sharing links)?
- [ ] BLE mesh for offline group tracking: v2 scope or too early?

---

*Next document: [TECH_STACK.md](TECH_STACK.md) — detailed technical decisions and ADRs*
*Next document: [USER_FLOWS.md](USER_FLOWS.md) — screen-by-screen user journey*
