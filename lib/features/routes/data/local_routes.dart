enum RouteShape {
  circular,      // loop — start and end at the same point
  linearOneWay,  // point-to-point, no return
  linearOutBack; // out-and-back on the same trail

  String get label => switch (this) {
    RouteShape.circular     => 'Circular',
    RouteShape.linearOneWay => 'One-way',
    RouteShape.linearOutBack => 'Out & back',
  };
}

class LocalRoute {
  const LocalRoute({
    required this.id,
    required this.name,
    required this.gpxAsset,
    required this.difficulty,
    required this.activityType,
    required this.shape,
    required this.description,
    this.rating = 0.0,
    this.reviewCount = 0,
  });

  final String id;
  final String name;
  final String gpxAsset;
  final String difficulty;   // 'Easy' | 'Moderate' | 'Hard' | 'Expert'
  final String activityType;
  final RouteShape shape;
  final String description;
  final double rating;
  final int reviewCount;
}

const localRoutes = <LocalRoute>[
  LocalRoute(
    id: 'riscos-maliciosa',
    name: 'Riscos de la Maliciosa',
    gpxAsset: 'assets/routes/riscos_de_la_maliciosa.gpx',
    difficulty: 'Hard',
    activityType: 'hike',
    shape: RouteShape.circular,
    description:
        'Ruta circular por los riscos de La Maliciosa en la Sierra de Guadarrama. '
        'Itinerario de montaña con vistas espectaculares al valle del Lozoya y la cumbre de Peñalara. '
        'El tramo de los riscos requiere algo de manos, especialmente en la bajada.',
    rating: 4.7,
    reviewCount: 312,
  ),
];

LocalRoute? routeById(String id) {
  try {
    return localRoutes.firstWhere((r) => r.id == id);
  } catch (_) {
    return null;
  }
}
