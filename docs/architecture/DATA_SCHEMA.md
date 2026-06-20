# Sendero — Data Schema

**Version:** 0.1
**Date:** 2026-06-20

Sendero uses a dual-database architecture:
- **Local (device):** SQLite via Drift — source of truth for all writes
- **Remote (cloud):** Supabase Postgres with PostGIS — sync target, community data

Every table exists in both layers. The local schema is a structural subset of the remote schema (remote adds audit columns, PostGIS geometry, and multi-user constraints).

---

## 1. Entity Relationship Diagram

```
┌──────────┐       ┌────────────────┐       ┌──────────────────┐
│  users   │──1:N──│    routes      │──1:N──│  route_waypoints │
└──────────┘       └────────────────┘       └──────────────────┘
     │                    │ 1:N                       
     │ 1:N                ▼                           
     │             ┌─────────────┐                    
     │             │route_photos │                    
     │             └─────────────┘                    
     │                                                
     │ 1:N         ┌────────────────┐                 
     └────────────►│    tracks      │                 
                   └────────────────┘                 
                          │ 1:N                       
                          ├──────────────────────────►┌─────────────┐
                          │                           │track_points │
                          │ 1:N                       └─────────────┘
                          ▼
                   ┌─────────────┐
                   │track_photos │
                   └─────────────┘

┌──────────┐       ┌──────────────────┐
│  users   │──1:N──│offline_packages  │
└──────────┘       └──────────────────┘

┌──────────┐──M:N──┌────────────────┐   (via saved_routes join table)
│  users   │       │    routes      │
└──────────┘       └────────────────┘

┌──────────┐──M:N──┌──────────┐         (via follows join table)
│  users   │       │  users   │
└──────────┘       └──────────┘

┌──────────┐──1:N──┌────────────────┐
│  users   │       │    reviews     │──N:1──┌────────────────┐
└──────────┘       └────────────────┘       │    routes      │
                                            └────────────────┘
```

---

## 2. Local Schema (SQLite / Drift)

### 2.1 `users`

Stores only the authenticated user's own profile locally.

```sql
CREATE TABLE users (
  id              TEXT PRIMARY KEY,          -- UUID, matches Supabase auth.uid()
  email           TEXT NOT NULL UNIQUE,
  display_name    TEXT NOT NULL,
  avatar_url      TEXT,                      -- URL to Supabase Storage or null
  bio             TEXT,
  units           TEXT NOT NULL DEFAULT 'metric',  -- 'metric' | 'imperial'
  gps_mode        TEXT NOT NULL DEFAULT 'standard', -- 'precision'|'standard'|'eco'
  language        TEXT NOT NULL DEFAULT 'en',
  is_premium      INTEGER NOT NULL DEFAULT 0,  -- 0=free, 1=explorer, 2=creator
  premium_until   INTEGER,                   -- Unix timestamp, null if free
  created_at      INTEGER NOT NULL,
  updated_at      INTEGER NOT NULL,
  synced_at       INTEGER                    -- null = local-only / pending sync
);
```

### 2.2 `routes`

A route is a published or draft path that other users can discover and follow.

```sql
CREATE TABLE routes (
  id              TEXT PRIMARY KEY,          -- UUID
  title           TEXT NOT NULL,
  description     TEXT,
  author_id       TEXT NOT NULL,
  activity_type   TEXT NOT NULL,             -- 'hike'|'bike'|'run'|'ski'|'kayak'|...
  difficulty      INTEGER NOT NULL,          -- 1 (easiest) to 5 (hardest)
  
  -- Geometry stored as encoded polyline (local); PostGIS in remote
  encoded_path    TEXT NOT NULL,             -- Google encoded polyline v2
  
  -- Bounding box for spatial queries without decoding path
  bbox_min_lat    REAL NOT NULL,
  bbox_min_lon    REAL NOT NULL,
  bbox_max_lat    REAL NOT NULL,
  bbox_max_lon    REAL NOT NULL,
  
  -- Stats (derived from path, stored for fast display)
  distance_m      REAL NOT NULL,
  elevation_gain_m  REAL NOT NULL DEFAULT 0,
  elevation_loss_m  REAL NOT NULL DEFAULT 0,
  min_elevation_m   REAL,
  max_elevation_m   REAL,
  estimated_duration_s INTEGER,             -- computed from distance + activity type
  
  -- Locality (reverse-geocoded from start point)
  country_code    TEXT,                      -- ISO 3166-1 alpha-2
  region          TEXT,                      -- state/province/community
  locality        TEXT,                      -- city/town/village
  
  -- State
  is_public       INTEGER NOT NULL DEFAULT 0,
  is_deleted      INTEGER NOT NULL DEFAULT 0,
  is_downloaded   INTEGER NOT NULL DEFAULT 0, -- has offline tiles
  
  -- Community (cached from remote, not authoritative locally)
  cached_rating   REAL,
  cached_review_count INTEGER DEFAULT 0,
  cached_save_count   INTEGER DEFAULT 0,
  
  created_at      INTEGER NOT NULL,
  updated_at      INTEGER NOT NULL,
  synced_at       INTEGER
);

CREATE INDEX idx_routes_bbox ON routes (bbox_min_lat, bbox_min_lon, bbox_max_lat, bbox_max_lon);
CREATE INDEX idx_routes_author ON routes (author_id);
CREATE INDEX idx_routes_activity ON routes (activity_type);
CREATE INDEX idx_routes_public ON routes (is_public, is_deleted);
```

### 2.3 `route_waypoints`

Named points of interest along a route (summit, viewpoint, water source, parking, etc.)

```sql
CREATE TABLE route_waypoints (
  id              TEXT PRIMARY KEY,
  route_id        TEXT NOT NULL REFERENCES routes(id) ON DELETE CASCADE,
  sequence        INTEGER NOT NULL,          -- display order along route
  lat             REAL NOT NULL,
  lon             REAL NOT NULL,
  elevation_m     REAL,
  title           TEXT NOT NULL,
  description     TEXT,
  waypoint_type   TEXT NOT NULL DEFAULT 'generic',
                  -- 'start'|'finish'|'summit'|'viewpoint'|'water'|'shelter'|
                  -- 'parking'|'danger'|'info'|'generic'
  photo_url       TEXT,
  created_at      INTEGER NOT NULL,
  updated_at      INTEGER NOT NULL,
  synced_at       INTEGER
);

CREATE INDEX idx_waypoints_route ON route_waypoints (route_id, sequence);
```

### 2.4 `tracks`

A track is a raw GPS recording of an activity (a user's session in the field).

```sql
CREATE TABLE tracks (
  id              TEXT PRIMARY KEY,
  user_id         TEXT NOT NULL,
  route_id        TEXT REFERENCES routes(id), -- null if free-roaming
  
  title           TEXT NOT NULL,
  description     TEXT,
  activity_type   TEXT NOT NULL,
  
  -- Timing
  started_at      INTEGER NOT NULL,          -- Unix timestamp ms
  finished_at     INTEGER,                   -- null while recording in progress
  duration_s      INTEGER,                   -- null while recording
  
  -- Stats (computed on finish)
  distance_m      REAL,
  elevation_gain_m  REAL,
  elevation_loss_m  REAL,
  avg_speed_ms    REAL,
  max_speed_ms    REAL,
  avg_heart_rate  INTEGER,                   -- bpm, if HR sensor connected
  max_heart_rate  INTEGER,
  calories        INTEGER,                   -- estimated
  
  -- State
  status          TEXT NOT NULL DEFAULT 'recording',
                  -- 'recording'|'paused'|'finished'|'deleted'
  is_public       INTEGER NOT NULL DEFAULT 0,
  
  -- The full encoded track (Douglas-Peucker simplified, for display)
  encoded_path    TEXT,                      -- null while recording
  
  -- Bounding box
  bbox_min_lat    REAL,
  bbox_min_lon    REAL,
  bbox_max_lat    REAL,
  bbox_max_lon    REAL,
  
  created_at      INTEGER NOT NULL,
  updated_at      INTEGER NOT NULL,
  synced_at       INTEGER
);

CREATE INDEX idx_tracks_user ON tracks (user_id, started_at DESC);
CREATE INDEX idx_tracks_status ON tracks (status);
```

### 2.5 `track_points`

Raw GPS stream — one row per sample. Highest-frequency table in the system.

```sql
CREATE TABLE track_points (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  track_id        TEXT NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
  
  lat             REAL NOT NULL,
  lon             REAL NOT NULL,
  elevation_m     REAL,                      -- from GPS (may be null) or SRTM
  elevation_source TEXT,                     -- 'gps'|'srtm'|null
  
  accuracy_m      REAL,                      -- horizontal accuracy in meters
  speed_ms        REAL,                      -- m/s
  bearing_deg     REAL,                      -- 0–360
  heart_rate      INTEGER,                   -- bpm, null if no sensor
  
  recorded_at     INTEGER NOT NULL,          -- Unix timestamp ms
  
  -- Filtering flags
  is_filtered     INTEGER NOT NULL DEFAULT 0 -- 1 = excluded from stats (GPS spike)
);

-- Optimized for sequential reads during track finalization and export
CREATE INDEX idx_track_points_track_time ON track_points (track_id, recorded_at ASC);
```

**Storage estimate:** At standard mode (5s interval), a 4-hour hike = 2,880 points × ~60 bytes = ~170 KB per activity. 100 activities ≈ 17 MB. Well within device storage.

### 2.6 `offline_packages`

Tracks downloaded map tile packages.

```sql
CREATE TABLE offline_packages (
  id              TEXT PRIMARY KEY,
  
  -- Human-readable name (auto-generated or user-set)
  name            TEXT NOT NULL,
  
  -- Bounding box of the downloaded area
  bbox_min_lat    REAL NOT NULL,
  bbox_min_lon    REAL NOT NULL,
  bbox_max_lat    REAL NOT NULL,
  bbox_max_lon    REAL NOT NULL,
  
  -- Local file path to the .pmtiles file
  tile_path       TEXT NOT NULL UNIQUE,
  
  -- Download metadata
  size_bytes      INTEGER NOT NULL,
  tile_source_url TEXT NOT NULL,             -- CDN URL used to download
  tile_version    TEXT NOT NULL,             -- OSM data version / date
  
  -- State
  status          TEXT NOT NULL DEFAULT 'downloading',
                  -- 'downloading'|'ready'|'updating'|'error'
  download_progress REAL,                    -- 0.0 to 1.0
  error_message   TEXT,
  
  downloaded_at   INTEGER,
  expires_at      INTEGER,                   -- when to offer update (3 months)
  created_at      INTEGER NOT NULL,
  updated_at      INTEGER NOT NULL
);

CREATE INDEX idx_packages_bbox ON offline_packages (bbox_min_lat, bbox_min_lon, bbox_max_lat, bbox_max_lon);
```

### 2.7 `saved_routes`

User's saved (bookmarked) routes from the community.

```sql
CREATE TABLE saved_routes (
  user_id         TEXT NOT NULL,
  route_id        TEXT NOT NULL REFERENCES routes(id) ON DELETE CASCADE,
  saved_at        INTEGER NOT NULL,
  PRIMARY KEY (user_id, route_id)
);
```

### 2.8 `sync_queue`

Pending operations waiting to be flushed to Supabase.

```sql
CREATE TABLE sync_queue (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  entity_type     TEXT NOT NULL,             -- 'route'|'track'|'waypoint'|...
  entity_id       TEXT NOT NULL,
  operation       TEXT NOT NULL,             -- 'upsert'|'delete'
  payload         TEXT NOT NULL,             -- JSON
  priority        INTEGER NOT NULL DEFAULT 5, -- 1 (urgent) to 10 (background)
  attempt_count   INTEGER NOT NULL DEFAULT 0,
  last_error      TEXT,
  next_retry_at   INTEGER,                   -- exponential backoff
  created_at      INTEGER NOT NULL
);

CREATE INDEX idx_sync_queue_priority ON sync_queue (priority ASC, next_retry_at ASC);
CREATE INDEX idx_sync_queue_entity ON sync_queue (entity_type, entity_id);
```

### 2.9 `photos`

Locally cached photo metadata (files stored in app documents directory).

```sql
CREATE TABLE photos (
  id              TEXT PRIMARY KEY,
  entity_type     TEXT NOT NULL,             -- 'track'|'route'|'waypoint'
  entity_id       TEXT NOT NULL,
  
  local_path      TEXT NOT NULL,             -- absolute path on device
  remote_url      TEXT,                      -- Supabase Storage URL (null until synced)
  
  lat             REAL,
  lon             REAL,
  taken_at        INTEGER,                   -- EXIF timestamp
  
  width_px        INTEGER,
  height_px       INTEGER,
  size_bytes      INTEGER,
  
  caption         TEXT,
  sequence        INTEGER NOT NULL DEFAULT 0,
  
  upload_status   TEXT NOT NULL DEFAULT 'pending',
                  -- 'pending'|'uploading'|'uploaded'|'error'
  created_at      INTEGER NOT NULL,
  synced_at       INTEGER
);

CREATE INDEX idx_photos_entity ON photos (entity_type, entity_id, sequence);
```

---

## 3. Remote Schema (Supabase Postgres)

Extends the local schema with PostGIS geometry, community features, RLS, and audit trails.

### 3.1 Extensions

```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";        -- fuzzy text search
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";
```

### 3.2 `public.users`

```sql
CREATE TABLE public.users (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  auth_id         UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  email           TEXT NOT NULL UNIQUE,
  display_name    TEXT NOT NULL CHECK (char_length(display_name) BETWEEN 2 AND 50),
  avatar_url      TEXT,
  bio             TEXT CHECK (char_length(bio) <= 500),
  units           TEXT NOT NULL DEFAULT 'metric' CHECK (units IN ('metric', 'imperial')),
  language        TEXT NOT NULL DEFAULT 'en',
  
  -- Subscription
  tier            TEXT NOT NULL DEFAULT 'free' CHECK (tier IN ('free', 'explorer', 'creator', 'territory')),
  tier_expires_at TIMESTAMPTZ,
  
  -- Stats (denormalized, updated by triggers)
  total_distance_m    BIGINT NOT NULL DEFAULT 0,
  total_elevation_m   INTEGER NOT NULL DEFAULT 0,
  total_activities    INTEGER NOT NULL DEFAULT 0,
  routes_published    INTEGER NOT NULL DEFAULT 0,
  follower_count      INTEGER NOT NULL DEFAULT 0,
  following_count     INTEGER NOT NULL DEFAULT 0,
  
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at      TIMESTAMPTZ                        -- soft delete for GDPR
);

CREATE INDEX idx_users_display_name_trgm ON public.users USING gin (display_name gin_trgm_ops);
```

### 3.3 `public.routes`

```sql
CREATE TABLE public.routes (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  title           TEXT NOT NULL CHECK (char_length(title) BETWEEN 3 AND 200),
  description     TEXT CHECK (char_length(description) <= 5000),
  author_id       UUID NOT NULL REFERENCES public.users(id),
  activity_type   TEXT NOT NULL,
  difficulty      SMALLINT NOT NULL CHECK (difficulty BETWEEN 1 AND 5),
  
  -- PostGIS geometry (SRID 4326 = WGS84)
  geom            GEOGRAPHY(LINESTRING, 4326) NOT NULL,
  start_point     GEOGRAPHY(POINT, 4326) GENERATED ALWAYS AS (ST_StartPoint(geom::geometry)::geography) STORED,
  
  -- Bounding box (indexed for fast spatial search)
  bbox            GEOGRAPHY(POLYGON, 4326) GENERATED ALWAYS AS (ST_Envelope(geom::geometry)::geography) STORED,
  
  -- Stats
  distance_m      REAL NOT NULL,
  elevation_gain_m  REAL NOT NULL DEFAULT 0,
  elevation_loss_m  REAL NOT NULL DEFAULT 0,
  min_elevation_m   REAL,
  max_elevation_m   REAL,
  estimated_duration_s INTEGER,
  
  -- Locality
  country_code    CHAR(2),
  region          TEXT,
  locality        TEXT,
  
  -- Community stats (updated by triggers)
  avg_rating      REAL,
  review_count    INTEGER NOT NULL DEFAULT 0,
  save_count      INTEGER NOT NULL DEFAULT 0,
  download_count  INTEGER NOT NULL DEFAULT 0,
  view_count      INTEGER NOT NULL DEFAULT 0,
  
  -- State
  is_public       BOOLEAN NOT NULL DEFAULT FALSE,
  is_deleted      BOOLEAN NOT NULL DEFAULT FALSE,
  
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Spatial index for proximity queries
CREATE INDEX idx_routes_geom ON public.routes USING GIST (geom);
CREATE INDEX idx_routes_start_point ON public.routes USING GIST (start_point);
CREATE INDEX idx_routes_bbox ON public.routes USING GIST (bbox);

-- Filter indexes
CREATE INDEX idx_routes_public ON public.routes (is_public, is_deleted, activity_type);
CREATE INDEX idx_routes_author ON public.routes (author_id, created_at DESC);
CREATE INDEX idx_routes_rating ON public.routes (avg_rating DESC NULLS LAST) WHERE is_public AND NOT is_deleted;

-- Full-text search
CREATE INDEX idx_routes_title_trgm ON public.routes USING gin (title gin_trgm_ops);
```

### 3.4 `public.route_waypoints`

```sql
CREATE TABLE public.route_waypoints (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  route_id        UUID NOT NULL REFERENCES public.routes(id) ON DELETE CASCADE,
  sequence        SMALLINT NOT NULL,
  geom            GEOGRAPHY(POINT, 4326) NOT NULL,
  elevation_m     REAL,
  title           TEXT NOT NULL CHECK (char_length(title) BETWEEN 1 AND 100),
  description     TEXT CHECK (char_length(description) <= 1000),
  waypoint_type   TEXT NOT NULL DEFAULT 'generic',
  photo_url       TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (route_id, sequence)
);

CREATE INDEX idx_waypoints_route ON public.route_waypoints (route_id, sequence);
```

### 3.5 `public.tracks`

```sql
CREATE TABLE public.tracks (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID NOT NULL REFERENCES public.users(id),
  route_id        UUID REFERENCES public.routes(id),
  
  title           TEXT NOT NULL,
  description     TEXT,
  activity_type   TEXT NOT NULL,
  
  started_at      TIMESTAMPTZ NOT NULL,
  finished_at     TIMESTAMPTZ,
  duration_s      INTEGER,
  
  -- Stats
  distance_m      REAL,
  elevation_gain_m  REAL,
  elevation_loss_m  REAL,
  avg_speed_ms    REAL,
  max_speed_ms    REAL,
  avg_heart_rate  SMALLINT,
  max_heart_rate  SMALLINT,
  calories        INTEGER,
  
  -- PostGIS geometry
  geom            GEOGRAPHY(LINESTRING, 4326),  -- simplified for display
  
  -- Raw points stored separately (track_points table)
  
  status          TEXT NOT NULL DEFAULT 'finished',
  is_public       BOOLEAN NOT NULL DEFAULT FALSE,
  
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_tracks_user ON public.tracks (user_id, started_at DESC);
CREATE INDEX idx_tracks_geom ON public.tracks USING GIST (geom) WHERE geom IS NOT NULL;
```

### 3.6 `public.track_points`

Raw GPS stream. Uses TimescaleDB hypertable pattern if volume demands it, otherwise partitioned by month.

```sql
CREATE TABLE public.track_points (
  id              BIGSERIAL,
  track_id        UUID NOT NULL REFERENCES public.tracks(id) ON DELETE CASCADE,
  recorded_at     TIMESTAMPTZ NOT NULL,
  
  lat             REAL NOT NULL,
  lon             REAL NOT NULL,
  elevation_m     REAL,
  elevation_source TEXT,
  accuracy_m      REAL,
  speed_ms        REAL,
  bearing_deg     REAL,
  heart_rate      SMALLINT,
  is_filtered     BOOLEAN NOT NULL DEFAULT FALSE,
  
  PRIMARY KEY (id, recorded_at)
) PARTITION BY RANGE (recorded_at);

-- Monthly partitions (created by a scheduled Edge Function)
CREATE TABLE track_points_2026_06 PARTITION OF public.track_points
  FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');

CREATE INDEX idx_tp_track_time ON public.track_points (track_id, recorded_at ASC);
```

### 3.7 `public.reviews`

```sql
CREATE TABLE public.reviews (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  route_id        UUID NOT NULL REFERENCES public.routes(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES public.users(id),
  rating          SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  body            TEXT CHECK (char_length(body) <= 2000),
  track_id        UUID REFERENCES public.tracks(id), -- the activity this review is based on
  visited_at      DATE,
  condition       TEXT,                              -- 'excellent'|'good'|'poor'|'closed'
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (route_id, user_id)                         -- one review per user per route
);

CREATE INDEX idx_reviews_route ON public.reviews (route_id, created_at DESC);
CREATE INDEX idx_reviews_user ON public.reviews (user_id);
```

### 3.8 `public.saved_routes`

```sql
CREATE TABLE public.saved_routes (
  user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  route_id        UUID NOT NULL REFERENCES public.routes(id) ON DELETE CASCADE,
  saved_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, route_id)
);

CREATE INDEX idx_saved_routes_user ON public.saved_routes (user_id, saved_at DESC);
```

### 3.9 `public.follows`

```sql
CREATE TABLE public.follows (
  follower_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  following_id    UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (follower_id, following_id),
  CHECK (follower_id != following_id)
);

CREATE INDEX idx_follows_following ON public.follows (following_id);
```

### 3.10 `public.photos`

```sql
CREATE TABLE public.photos (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  uploader_id     UUID NOT NULL REFERENCES public.users(id),
  entity_type     TEXT NOT NULL CHECK (entity_type IN ('track', 'route', 'waypoint')),
  entity_id       UUID NOT NULL,
  
  storage_path    TEXT NOT NULL UNIQUE,              -- path within Supabase Storage bucket
  url             TEXT NOT NULL,                     -- public CDN URL
  thumbnail_url   TEXT,                              -- 300×300 thumbnail
  
  geom            GEOGRAPHY(POINT, 4326),
  taken_at        TIMESTAMPTZ,
  
  width_px        INTEGER,
  height_px       INTEGER,
  size_bytes      INTEGER,
  
  caption         TEXT CHECK (char_length(caption) <= 500),
  sequence        SMALLINT NOT NULL DEFAULT 0,
  
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_photos_entity ON public.photos (entity_type, entity_id, sequence);
```

---

## 4. Triggers & Denormalization

### 4.1 Update route stats on review change

```sql
CREATE OR REPLACE FUNCTION update_route_review_stats()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.routes SET
    avg_rating   = (SELECT AVG(rating) FROM public.reviews WHERE route_id = COALESCE(NEW.route_id, OLD.route_id)),
    review_count = (SELECT COUNT(*) FROM public.reviews WHERE route_id = COALESCE(NEW.route_id, OLD.route_id)),
    updated_at   = NOW()
  WHERE id = COALESCE(NEW.route_id, OLD.route_id);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_route_review_stats
  AFTER INSERT OR UPDATE OR DELETE ON public.reviews
  FOR EACH ROW EXECUTE FUNCTION update_route_review_stats();
```

### 4.2 Update user stats on track insert

```sql
CREATE OR REPLACE FUNCTION update_user_track_stats()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NEW.status = 'finished' THEN
    UPDATE public.users SET
      total_distance_m  = total_distance_m + COALESCE(NEW.distance_m, 0),
      total_elevation_m = total_elevation_m + COALESCE(NEW.elevation_gain_m, 0),
      total_activities  = total_activities + 1,
      updated_at        = NOW()
    WHERE id = NEW.user_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_user_track_stats
  AFTER INSERT ON public.tracks
  FOR EACH ROW EXECUTE FUNCTION update_user_track_stats();
```

### 4.3 Update follower counts

```sql
CREATE OR REPLACE FUNCTION update_follow_counts()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.users SET follower_count  = follower_count + 1  WHERE id = NEW.following_id;
    UPDATE public.users SET following_count = following_count + 1 WHERE id = NEW.follower_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.users SET follower_count  = GREATEST(follower_count - 1, 0)  WHERE id = OLD.following_id;
    UPDATE public.users SET following_count = GREATEST(following_count - 1, 0) WHERE id = OLD.follower_id;
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_follow_counts
  AFTER INSERT OR DELETE ON public.follows
  FOR EACH ROW EXECUTE FUNCTION update_follow_counts();
```

### 4.4 Auto-update `updated_at`

```sql
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Applied to all mutable tables
CREATE TRIGGER trg_updated_at BEFORE UPDATE ON public.users    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_updated_at BEFORE UPDATE ON public.routes   FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_updated_at BEFORE UPDATE ON public.tracks   FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_updated_at BEFORE UPDATE ON public.reviews  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
```

---

## 5. Row-Level Security (RLS)

```sql
-- ════════════════════════════════════════
-- users
-- ════════════════════════════════════════
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- Anyone can read non-deleted public profiles
CREATE POLICY "users: public read"
  ON public.users FOR SELECT
  USING (deleted_at IS NULL);

-- Users can only update their own profile
CREATE POLICY "users: self update"
  ON public.users FOR UPDATE
  USING (auth_id = auth.uid());

-- ════════════════════════════════════════
-- routes
-- ════════════════════════════════════════
ALTER TABLE public.routes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "routes: public read"
  ON public.routes FOR SELECT
  USING (is_public = TRUE AND is_deleted = FALSE);

CREATE POLICY "routes: author read own"
  ON public.routes FOR SELECT
  USING (author_id = (SELECT id FROM public.users WHERE auth_id = auth.uid()));

CREATE POLICY "routes: author insert"
  ON public.routes FOR INSERT
  WITH CHECK (author_id = (SELECT id FROM public.users WHERE auth_id = auth.uid()));

CREATE POLICY "routes: author update"
  ON public.routes FOR UPDATE
  USING (author_id = (SELECT id FROM public.users WHERE auth_id = auth.uid()));

CREATE POLICY "routes: author soft delete"
  ON public.routes FOR UPDATE
  USING (author_id = (SELECT id FROM public.users WHERE auth_id = auth.uid()));

-- ════════════════════════════════════════
-- tracks
-- ════════════════════════════════════════
ALTER TABLE public.tracks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tracks: public read"
  ON public.tracks FOR SELECT
  USING (is_public = TRUE);

CREATE POLICY "tracks: owner full access"
  ON public.tracks FOR ALL
  USING (user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid()));

-- ════════════════════════════════════════
-- track_points
-- ════════════════════════════════════════
ALTER TABLE public.track_points ENABLE ROW LEVEL SECURITY;

-- Only accessible via tracks policy (owner of track)
CREATE POLICY "track_points: owner access"
  ON public.track_points FOR ALL
  USING (
    track_id IN (
      SELECT id FROM public.tracks
      WHERE user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid())
    )
  );

-- ════════════════════════════════════════
-- reviews
-- ════════════════════════════════════════
ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;

CREATE POLICY "reviews: public read"
  ON public.reviews FOR SELECT USING (TRUE);

CREATE POLICY "reviews: author write"
  ON public.reviews FOR ALL
  USING (user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid()));

-- ════════════════════════════════════════
-- saved_routes
-- ════════════════════════════════════════
ALTER TABLE public.saved_routes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "saved_routes: owner access"
  ON public.saved_routes FOR ALL
  USING (user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid()));
```

---

## 6. Key Queries

### Nearby routes (spatial search)

```sql
-- Routes within 20 km of a point, ordered by distance
SELECT
  r.id, r.title, r.activity_type, r.difficulty,
  r.distance_m, r.elevation_gain_m, r.avg_rating,
  ST_Distance(r.start_point, ST_MakePoint($lon, $lat)::geography) AS distance_from_user
FROM public.routes r
WHERE
  r.is_public = TRUE
  AND r.is_deleted = FALSE
  AND ST_DWithin(r.start_point, ST_MakePoint($lon, $lat)::geography, 20000)
  AND ($activity_type IS NULL OR r.activity_type = $activity_type)
  AND ($difficulty IS NULL OR r.difficulty = $difficulty)
ORDER BY distance_from_user ASC
LIMIT 50;
```

### Full-text route search

```sql
SELECT id, title, activity_type, difficulty, distance_m, avg_rating,
       similarity(title, $query) AS rank
FROM public.routes
WHERE is_public AND NOT is_deleted
  AND title % $query  -- trigram similarity threshold
ORDER BY rank DESC, avg_rating DESC NULLS LAST
LIMIT 20;
```

### Routes intersecting a bounding box (for map view)

```sql
SELECT id, title, activity_type, difficulty, avg_rating,
       ST_AsEncodedPolyline(geom::geometry) AS encoded_path
FROM public.routes
WHERE is_public AND NOT is_deleted
  AND geom && ST_MakeEnvelope($min_lon, $min_lat, $max_lon, $max_lat, 4326)::geography
LIMIT 200;
```

### User activity feed (following)

```sql
SELECT t.id, t.title, t.activity_type, t.distance_m, t.elevation_gain_m,
       t.started_at, t.duration_s,
       u.display_name, u.avatar_url
FROM public.tracks t
JOIN public.users u ON u.id = t.user_id
WHERE
  t.is_public = TRUE
  AND t.user_id IN (
    SELECT following_id FROM public.follows WHERE follower_id = $current_user_id
  )
ORDER BY t.started_at DESC
LIMIT 30;
```

---

*Related: [SYNC_PROTOCOL.md](SYNC_PROTOCOL.md) — how local and remote stay in sync*
*Related: [API_DESIGN.md](API_DESIGN.md) — client-facing API contracts*
