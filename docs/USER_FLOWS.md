# Sendero — User Flows

**Version:** 0.1
**Date:** 2026-06-20

---

## Flow 1: First-Time User (no account)

```
App opens
    │
    ▼
Onboarding screen (3 slides, skippable)
    │  Slide 1: "Track anywhere. Even offline."
    │  Slide 2: "Download maps before you go."
    │  Slide 3: "Free. Always."
    │
    ▼
[Skip / Get Started]
    │
    ▼
Map screen (home) — location permission requested
    │
    ├── [Deny location] → Map centered on last known / IP location
    │                      Track button disabled with explanation
    │
    └── [Allow] → Map centers on user location
                   Track button active
                   Soft prompt: "Create account to save your tracks?"
                   (dismissible, appears after 3 tracks recorded)
```

---

## Flow 2: Start a Tracking Session

```
Home (Map screen)
    │
[Tap Track button — large FAB, always visible]
    │
    ▼
Pre-session sheet (slides up)
    │  Activity type selector: 🥾 Hike  🚴 Bike  🏃 Run  ⛷ Ski  ...
    │  Tracking mode: Precision / Standard (default) / Eco
    │  Optional: Select a route to follow (search or browse nearby)
    │
[Start]
    │
    ▼
Tracking screen (full-screen map)
    │  Stats bar (top): Distance | Time | Pace | Elevation gain
    │  Map: live position dot + breadcrumb trail
    │  Elevation profile (bottom, collapsible)
    │  Waypoint button (add POI mid-track)
    │  Pause / Stop buttons
    │
[Stop]
    │
    ▼
Save activity sheet
    │  Title (auto-generated: "Morning Hike · Jun 20")
    │  Activity summary: distance, time, elevation, map thumbnail
    │  Visibility: Private / Public
    │  Add photos (from camera roll or camera)
    │  Tags: #easy #family #viewpoint ...
    │
[Save]
    │
    ▼
Activity detail screen
    │  Full stats + map + elevation profile
    │  Shareable summary card (image)
    │  "Publish as Route" button (creates discoverable route from this track)
    │
    ▼
[If offline] → Saved locally, badge: "Sync pending"
[When online] → Auto-syncs silently, badge disappears
```

---

## Flow 3: Download Maps for Offline Use

```
Home screen
    │
[Tap map area with long press / or via Settings > Offline Maps]
    │
    ▼
"Download this area" bottom sheet
    │  Visible area on screen shown as download region (adjustable)
    │  Estimated size: X MB
    │  Includes: Base map + trails + elevation + contour lines
    │
[Download]
    │
    ▼
Download progress (background, continues if app is minimized)
    │
    ▼
[Complete] → Notification: "Pyrenees Central downloaded (45 MB)"
    │
    ▼
Map works fully offline in that area:
    ├── Tiles render without network
    ├── Elevation profile calculated locally
    ├── Off-route detection works
    └── Waypoints and saved routes load from local DB
```

**Manage offline maps:**
```
Settings > Offline Maps
    │
    ▼
List of downloaded regions
    │  Each entry: name, size, download date, [Delete] button
    │  Total storage used
    │
[+ Download new area] → Returns to map for area selection
```

---

## Flow 4: Discover and Follow a Route

```
Home screen
    │
[Tap Search / Explore tab]
    │
    ▼
Explore screen
    │  Map view with route markers (colored by difficulty)
    │  List view toggle
    │  Filters: Activity type | Distance | Difficulty | Rating | Near me
    │
[Tap a route marker or list item]
    │
    ▼
Route detail screen
    │  Header: route name, author, rating (★ 4.3 · 156 reviews)
    │  Stats: 12.4 km · +640 m · ~3h 20min · Moderate
    │  Map preview (interactive)
    │  Elevation profile
    │  Description + waypoint list
    │  Photos (user-contributed)
    │  Recent activity feed (other users who did this route)
    │  Reviews section
    │
[Save route] → Added to My Routes library
[Download for offline] → Downloads map tiles for the route area + track
[Start navigation] → Goes to Pre-session sheet (Flow 2) with route pre-selected
```

---

## Flow 5: Navigate a Downloaded Route (offline)

```
[User is in the field, no signal]
    │
    ▼
Open Sendero (loads from cache, no network needed)
    │
    ▼
Home map screen — shows position, offline tiles render normally
    │
[My Routes → Select downloaded route → Start]
    │
    ▼
Tracking screen with route overlay
    │  Route line drawn on map
    │  Remaining distance to finish
    │  Next waypoint indicator
    │  Off-route alert if deviation > 50m (haptic + audio)
    │
[Reach finish / tap Stop]
    │
    ▼
Save screen (same as Flow 2)
    │
    ▼
[Back in coverage zone]
    │
    ▼
SyncService flushes track to Supabase automatically
    User notified: "Your activity has been synced"
```

---

## Flow 6: Create and Publish a Route

```
[Option A: Publish from recorded track]
    Activity detail → [Publish as Route]
    
[Option B: Draw a route manually]
    Home → Create → Draw on map (tap to add points)
    
[Option C: Import GPX]
    Home → Create → Import → Select .gpx file
    │
    ▼
Route editor
    │  Map with editable track (drag points, add/remove)
    │  Metadata form:
    │    Title, description, difficulty (1–5), activity type
    │    Tags, starting point (auto-detected)
    │    Waypoints: add name + description + photo per point
    │
[Preview] → Shows route as a discoverable card
    │
[Publish]
    │
    ▼
Route live on Sendero community
    │  Indexed for search
    │  Shareable link: sendero.app/routes/{id}
    │  Author gets notified of saves, downloads, reviews
```

---

## Flow 7: Account Creation (deferred, not forced)

```
Trigger: user tries to publish a route, or dismisses "save locally?" 
         prompt 3 times, or taps profile tab
    │
    ▼
Sign up screen
    │  [Continue with Google]
    │  [Continue with Apple]
    │  [Sign up with email]
    │
[OAuth path] → OS OAuth sheet → Account created → Profile setup
    │
[Email path]
    │  Enter email → Enter password → Verify email
    │
    ▼
Profile setup (optional, skippable)
    │  Display name, avatar, activity preferences
    │
    ▼
[Existing local data migration prompt]
    "We found 3 unsynced activities. Upload them to your account?"
    [Yes, upload all] / [No, keep local only]
    │
    ▼
Home screen — now with profile tab active, sync enabled
```

---

## Flow 8: Offline Group Location Sharing (v1.x)

```
[Before going offline — requires all members to be online to initiate]
    │
Leader taps: Home → Share Location → Create Group
    │
    ▼
Generates 6-character group code
    │
    ▼
Other members enter code → join group session
    │
    ▼
All members go offline
    │
    ▼
[Online via Supabase Realtime]
    Each member sees others' positions on map (live, 10s update)
    
[Offline via BLE mesh — v2.0 scope]
    Devices relay GPS positions peer-to-peer over Bluetooth
    Range: ~100m device-to-device, extended by chain
```

---

## Screen Map

```
App
├── Home (Map)
│   ├── Explore / Search overlay
│   ├── Route detail sheet
│   └── Track FAB → Tracking screen
│       └── Post-session save
│
├── My Routes
│   ├── Recorded activities
│   ├── Saved routes
│   ├── Downloaded (offline) packages
│   └── Created routes
│
├── Create
│   ├── Import GPX/KML/FIT
│   └── Draw on map
│
├── Profile
│   ├── Stats overview
│   ├── Activity history
│   ├── Following / Followers
│   └── Settings
│       ├── Offline Maps (manage downloads)
│       ├── Tracking (GPS mode, units, audio cues)
│       ├── Privacy
│       ├── Account
│       └── About / Licenses
│
└── Notifications
    ├── New follower
    ├── Activity liked / commented
    ├── Route reviewed
    └── Sync completed
```

---

*Related: [PRD.md](PRD.md) — product requirements*
*Related: [TECH_STACK.md](TECH_STACK.md) — technical decisions*
