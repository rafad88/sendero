-- Sendero — Initial Schema
-- Run this in the Supabase SQL Editor (Project > SQL Editor > New Query)
-- Execute each section sequentially.

-- ════════════════════════════════════════════════════════════
-- EXTENSIONS
-- ════════════════════════════════════════════════════════════

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- ════════════════════════════════════════════════════════════
-- USERS
-- ════════════════════════════════════════════════════════════

CREATE TABLE public.users (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  auth_id         UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  email           TEXT NOT NULL UNIQUE,
  display_name    TEXT NOT NULL CHECK (char_length(display_name) BETWEEN 2 AND 50),
  avatar_url      TEXT,
  bio             TEXT CHECK (char_length(bio) <= 500),
  units           TEXT NOT NULL DEFAULT 'metric' CHECK (units IN ('metric', 'imperial')),
  language        TEXT NOT NULL DEFAULT 'en',
  tier            TEXT NOT NULL DEFAULT 'free' CHECK (tier IN ('free', 'explorer', 'creator', 'territory')),
  tier_expires_at TIMESTAMPTZ,
  total_distance_m    BIGINT NOT NULL DEFAULT 0,
  total_elevation_m   INTEGER NOT NULL DEFAULT 0,
  total_activities    INTEGER NOT NULL DEFAULT 0,
  routes_published    INTEGER NOT NULL DEFAULT 0,
  follower_count      INTEGER NOT NULL DEFAULT 0,
  following_count     INTEGER NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at      TIMESTAMPTZ
);

CREATE INDEX idx_users_display_name_trgm ON public.users USING gin (display_name gin_trgm_ops);

-- Auto-create user profile on auth sign-up
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.users (auth_id, email, display_name)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'display_name', split_part(NEW.email, '@', 1))
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ════════════════════════════════════════════════════════════
-- ROUTES
-- ════════════════════════════════════════════════════════════

CREATE TABLE public.routes (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  title           TEXT NOT NULL CHECK (char_length(title) BETWEEN 3 AND 200),
  description     TEXT CHECK (char_length(description) <= 5000),
  author_id       UUID NOT NULL REFERENCES public.users(id),
  activity_type   TEXT NOT NULL,
  difficulty      SMALLINT NOT NULL CHECK (difficulty BETWEEN 1 AND 5),
  geom            GEOGRAPHY(LINESTRING, 4326) NOT NULL,
  distance_m      REAL NOT NULL,
  elevation_gain_m  REAL NOT NULL DEFAULT 0,
  elevation_loss_m  REAL NOT NULL DEFAULT 0,
  min_elevation_m   REAL,
  max_elevation_m   REAL,
  estimated_duration_s INTEGER,
  country_code    CHAR(2),
  region          TEXT,
  locality        TEXT,
  avg_rating      REAL,
  review_count    INTEGER NOT NULL DEFAULT 0,
  save_count      INTEGER NOT NULL DEFAULT 0,
  download_count  INTEGER NOT NULL DEFAULT 0,
  view_count      INTEGER NOT NULL DEFAULT 0,
  is_public       BOOLEAN NOT NULL DEFAULT FALSE,
  is_deleted      BOOLEAN NOT NULL DEFAULT FALSE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_routes_geom       ON public.routes USING GIST (geom);
CREATE INDEX idx_routes_public     ON public.routes (is_public, is_deleted, activity_type);
CREATE INDEX idx_routes_author     ON public.routes (author_id, created_at DESC);
CREATE INDEX idx_routes_rating     ON public.routes (avg_rating DESC NULLS LAST) WHERE is_public AND NOT is_deleted;
CREATE INDEX idx_routes_title_trgm ON public.routes USING gin (title gin_trgm_ops);

-- ════════════════════════════════════════════════════════════
-- ROUTE WAYPOINTS
-- ════════════════════════════════════════════════════════════

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

-- ════════════════════════════════════════════════════════════
-- TRACKS
-- ════════════════════════════════════════════════════════════

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
  distance_m      REAL,
  elevation_gain_m  REAL,
  elevation_loss_m  REAL,
  avg_speed_ms    REAL,
  max_speed_ms    REAL,
  avg_heart_rate  SMALLINT,
  max_heart_rate  SMALLINT,
  calories        INTEGER,
  geom            GEOGRAPHY(LINESTRING, 4326),
  status          TEXT NOT NULL DEFAULT 'finished',
  is_public       BOOLEAN NOT NULL DEFAULT FALSE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_tracks_user ON public.tracks (user_id, started_at DESC);
CREATE INDEX idx_tracks_geom ON public.tracks USING GIST (geom) WHERE geom IS NOT NULL;

-- ════════════════════════════════════════════════════════════
-- TRACK POINTS (partitioned by month)
-- ════════════════════════════════════════════════════════════

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

CREATE TABLE track_points_2026_06 PARTITION OF public.track_points
  FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE track_points_2026_07 PARTITION OF public.track_points
  FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
CREATE TABLE track_points_2026_08 PARTITION OF public.track_points
  FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE track_points_2026_09 PARTITION OF public.track_points
  FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE track_points_2026_10 PARTITION OF public.track_points
  FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');
CREATE TABLE track_points_2026_11 PARTITION OF public.track_points
  FOR VALUES FROM ('2026-11-01') TO ('2026-12-01');
CREATE TABLE track_points_2026_12 PARTITION OF public.track_points
  FOR VALUES FROM ('2026-12-01') TO ('2027-01-01');

CREATE INDEX idx_tp_track_time ON public.track_points (track_id, recorded_at ASC);

-- ════════════════════════════════════════════════════════════
-- REVIEWS
-- ════════════════════════════════════════════════════════════

CREATE TABLE public.reviews (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  route_id        UUID NOT NULL REFERENCES public.routes(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES public.users(id),
  rating          SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  body            TEXT CHECK (char_length(body) <= 2000),
  track_id        UUID REFERENCES public.tracks(id),
  visited_at      DATE,
  condition       TEXT CHECK (condition IN ('excellent','good','poor','closed')),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (route_id, user_id)
);

CREATE INDEX idx_reviews_route ON public.reviews (route_id, created_at DESC);

-- ════════════════════════════════════════════════════════════
-- SAVED ROUTES & FOLLOWS
-- ════════════════════════════════════════════════════════════

CREATE TABLE public.saved_routes (
  user_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  route_id    UUID NOT NULL REFERENCES public.routes(id) ON DELETE CASCADE,
  saved_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, route_id)
);

CREATE TABLE public.follows (
  follower_id   UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  following_id  UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (follower_id, following_id),
  CHECK (follower_id != following_id)
);

CREATE INDEX idx_follows_following ON public.follows (following_id);

-- ════════════════════════════════════════════════════════════
-- PHOTOS
-- ════════════════════════════════════════════════════════════

CREATE TABLE public.photos (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  uploader_id     UUID NOT NULL REFERENCES public.users(id),
  entity_type     TEXT NOT NULL CHECK (entity_type IN ('track', 'route', 'waypoint')),
  entity_id       UUID NOT NULL,
  storage_path    TEXT NOT NULL UNIQUE,
  url             TEXT NOT NULL,
  thumbnail_url   TEXT,
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

-- ════════════════════════════════════════════════════════════
-- TRIGGERS
-- ════════════════════════════════════════════════════════════

-- updated_at auto-update
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at   BEFORE UPDATE ON public.users   FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_routes_updated_at  BEFORE UPDATE ON public.routes  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_tracks_updated_at  BEFORE UPDATE ON public.tracks  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_reviews_updated_at BEFORE UPDATE ON public.reviews FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Route review stats
CREATE OR REPLACE FUNCTION update_route_review_stats()
RETURNS TRIGGER AS $$
DECLARE rid UUID;
BEGIN
  rid := COALESCE(NEW.route_id, OLD.route_id);
  UPDATE public.routes SET
    avg_rating   = (SELECT AVG(rating)  FROM public.reviews WHERE route_id = rid),
    review_count = (SELECT COUNT(*)     FROM public.reviews WHERE route_id = rid),
    updated_at   = NOW()
  WHERE id = rid;
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_route_review_stats
  AFTER INSERT OR UPDATE OR DELETE ON public.reviews
  FOR EACH ROW EXECUTE FUNCTION update_route_review_stats();

-- User stats on track finish
CREATE OR REPLACE FUNCTION update_user_track_stats()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NEW.status = 'finished' THEN
    UPDATE public.users SET
      total_distance_m  = total_distance_m + COALESCE(NEW.distance_m, 0),
      total_elevation_m = total_elevation_m + COALESCE(NEW.elevation_gain_m, 0)::INTEGER,
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

-- Follow counts
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

-- ════════════════════════════════════════════════════════════
-- ROW LEVEL SECURITY
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.users        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.routes       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.route_waypoints ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tracks       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.track_points ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reviews      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.saved_routes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.follows      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.photos       ENABLE ROW LEVEL SECURITY;

-- Users
CREATE POLICY "users: public read"  ON public.users FOR SELECT USING (deleted_at IS NULL);
CREATE POLICY "users: self update"  ON public.users FOR UPDATE USING (auth_id = auth.uid());

-- Routes
CREATE POLICY "routes: public read"  ON public.routes FOR SELECT USING (is_public AND NOT is_deleted);
CREATE POLICY "routes: author read"  ON public.routes FOR SELECT USING (author_id = (SELECT id FROM public.users WHERE auth_id = auth.uid()));
CREATE POLICY "routes: author write" ON public.routes FOR ALL    USING (author_id = (SELECT id FROM public.users WHERE auth_id = auth.uid()));

-- Waypoints (inherit route access)
CREATE POLICY "waypoints: public read" ON public.route_waypoints FOR SELECT
  USING (route_id IN (SELECT id FROM public.routes WHERE is_public AND NOT is_deleted));
CREATE POLICY "waypoints: author write" ON public.route_waypoints FOR ALL
  USING (route_id IN (SELECT id FROM public.routes WHERE author_id = (SELECT id FROM public.users WHERE auth_id = auth.uid())));

-- Tracks
CREATE POLICY "tracks: public read"    ON public.tracks FOR SELECT USING (is_public = TRUE);
CREATE POLICY "tracks: owner full"     ON public.tracks FOR ALL    USING (user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid()));

-- Track points (only owner)
CREATE POLICY "track_points: owner" ON public.track_points FOR ALL
  USING (track_id IN (SELECT id FROM public.tracks WHERE user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid())));

-- Reviews
CREATE POLICY "reviews: public read"   ON public.reviews FOR SELECT USING (TRUE);
CREATE POLICY "reviews: author write"  ON public.reviews FOR ALL    USING (user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid()));

-- Saved routes
CREATE POLICY "saved: owner access" ON public.saved_routes FOR ALL USING (user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid()));

-- Follows
CREATE POLICY "follows: public read"   ON public.follows FOR SELECT USING (TRUE);
CREATE POLICY "follows: owner write"   ON public.follows FOR ALL    USING (follower_id = (SELECT id FROM public.users WHERE auth_id = auth.uid()));

-- Photos (public read if entity is public, owner write)
CREATE POLICY "photos: public read"   ON public.photos FOR SELECT USING (TRUE);
CREATE POLICY "photos: owner write"   ON public.photos FOR ALL USING (uploader_id = (SELECT id FROM public.users WHERE auth_id = auth.uid()));

-- ════════════════════════════════════════════════════════════
-- SPATIAL QUERY FUNCTIONS
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION routes_near(
  user_lat       FLOAT,
  user_lon       FLOAT,
  radius_m       INTEGER DEFAULT 20000,
  activity_type  TEXT    DEFAULT NULL,
  min_difficulty INTEGER DEFAULT NULL,
  max_difficulty INTEGER DEFAULT NULL,
  min_distance_m FLOAT   DEFAULT NULL,
  max_distance_m FLOAT   DEFAULT NULL,
  sort_by        TEXT    DEFAULT 'distance',
  "limit"        INTEGER DEFAULT 50,
  "offset"       INTEGER DEFAULT 0
)
RETURNS TABLE (
  id UUID, title TEXT, activity_type TEXT, difficulty SMALLINT,
  distance_m REAL, elevation_gain_m REAL, avg_rating REAL,
  review_count INTEGER, save_count INTEGER,
  author_name TEXT, author_avatar TEXT,
  distance_from_user FLOAT, country_code CHAR(2), locality TEXT
)
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT
    r.id, r.title, r.activity_type, r.difficulty,
    r.distance_m, r.elevation_gain_m, r.avg_rating, r.review_count, r.save_count,
    u.display_name, u.avatar_url,
    ST_Distance(ST_StartPoint(r.geom::geometry)::geography, ST_MakePoint(user_lon, user_lat)::geography) AS dist,
    r.country_code, r.locality
  FROM public.routes r
  JOIN public.users u ON u.id = r.author_id
  WHERE
    r.is_public = TRUE AND r.is_deleted = FALSE
    AND ST_DWithin(ST_StartPoint(r.geom::geometry)::geography, ST_MakePoint(user_lon, user_lat)::geography, radius_m)
    AND (activity_type   IS NULL OR r.activity_type   = activity_type)
    AND (min_difficulty  IS NULL OR r.difficulty      >= min_difficulty)
    AND (max_difficulty  IS NULL OR r.difficulty      <= max_difficulty)
    AND (min_distance_m  IS NULL OR r.distance_m      >= min_distance_m)
    AND (max_distance_m  IS NULL OR r.distance_m      <= max_distance_m)
  ORDER BY
    CASE sort_by
      WHEN 'rating'  THEN -COALESCE(r.avg_rating, 0)
      WHEN 'newest'  THEN EXTRACT(EPOCH FROM r.created_at) * -1
      ELSE ST_Distance(ST_StartPoint(r.geom::geometry)::geography, ST_MakePoint(user_lon, user_lat)::geography)
    END
  LIMIT "limit" OFFSET "offset";
$$;

CREATE OR REPLACE FUNCTION search_routes(query TEXT, "limit" INTEGER DEFAULT 20)
RETURNS TABLE (id UUID, title TEXT, activity_type TEXT, difficulty SMALLINT, distance_m REAL, avg_rating REAL, rank REAL)
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT r.id, r.title, r.activity_type, r.difficulty, r.distance_m, r.avg_rating,
         similarity(r.title, query) AS rank
  FROM public.routes r
  WHERE r.is_public AND NOT r.is_deleted AND r.title % query
  ORDER BY rank DESC, avg_rating DESC NULLS LAST
  LIMIT "limit";
$$;
