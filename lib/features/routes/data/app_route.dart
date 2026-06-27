const _difficultyLabels = ['Easy', 'Moderate', 'Hard', 'Expert'];

enum RouteShape {
  circular,
  linearOneWay,
  linearOutBack;

  String get label => switch (this) {
    RouteShape.circular      => 'Circular',
    RouteShape.linearOneWay  => 'One-way',
    RouteShape.linearOutBack => 'Out & back',
  };

  static RouteShape fromString(String s) => switch (s) {
    'linearOneWay'  => RouteShape.linearOneWay,
    'linearOutBack' => RouteShape.linearOutBack,
    _               => RouteShape.circular,
  };
}

class AppRoute {
  const AppRoute({
    required this.id,
    required this.slug,
    required this.title,
    required this.activityType,
    required this.difficulty,
    required this.shape,
    required this.distanceM,
    required this.elevationGainM,
    required this.elevationLossM,
    required this.avgRating,
    required this.reviewCount,
    this.description,
    this.gpxPath,
    this.startLat,
    this.startLon,
    this.estimatedDurationS,
    this.countryCode,
    this.region,
    this.locality,
  });

  final String id;
  final String slug;
  final String title;
  final String activityType;
  final int difficulty;
  final RouteShape shape;
  final double distanceM;
  final double elevationGainM;
  final double elevationLossM;
  final double avgRating;
  final int reviewCount;
  final String? description;
  final String? gpxPath;
  final double? startLat;
  final double? startLon;
  final int? estimatedDurationS;
  final String? countryCode;
  final String? region;
  final String? locality;

  String get difficultyLabel => _difficultyLabels[difficulty.clamp(0, 3)];
  double get distanceKm => distanceM / 1000;

  factory AppRoute.fromSupabase(Map<String, dynamic> j) => AppRoute(
    id:                 j['id'] as String,
    slug:               (j['slug'] as String?) ?? j['id'] as String,
    title:              j['title'] as String,
    description:        j['description'] as String?,
    activityType:       (j['activity_type'] as String?) ?? 'hike',
    difficulty:         (j['difficulty'] as int?) ?? 1,
    shape:              RouteShape.fromString((j['shape'] as String?) ?? 'circular'),
    gpxPath:            j['gpx_path'] as String?,
    startLat:           (j['start_lat'] as num?)?.toDouble(),
    startLon:           (j['start_lon'] as num?)?.toDouble(),
    distanceM:          (j['distance_m'] as num?)?.toDouble() ?? 0,
    elevationGainM:     (j['elevation_gain_m'] as num?)?.toDouble() ?? 0,
    elevationLossM:     (j['elevation_loss_m'] as num?)?.toDouble() ?? 0,
    estimatedDurationS: j['estimated_duration_s'] as int?,
    avgRating:          (j['avg_rating'] as num?)?.toDouble() ?? 0,
    reviewCount:        (j['review_count'] as int?) ?? 0,
    countryCode:        j['country_code'] as String?,
    region:             j['region'] as String?,
    locality:           j['locality'] as String?,
  );
}
