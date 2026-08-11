enum ReferenceEllipsoid {
  clarke1880('Clarke 1880', 'Suitable for ARC 1950, ARC 1960 or MINNE'),
  clarke1866('Clarke 1866', 'Suitable for NAD27'),
  grs1980('GRS 1980', 'Suitable for NAD83, ETRS89'),
  grs1967('GRS 1967', 'Suitable for Transverse Mercator (TM) and Oblique Mercator (OM)'),
  wgs84('WGS 84', 'Suitable for UTM (Default)'),
  wgs72('WGS 72', ''),
  wgs66('WGS 66', ''),
  wgs60('WGS 60', '');

  final String displayName;
  final String description;

  const ReferenceEllipsoid(this.displayName, this.description);

  bool get isDefault => this == ReferenceEllipsoid.wgs84;

  static ReferenceEllipsoid fromRaw(String? raw) {
    for (final ellipsoid in values) {
      if (ellipsoid.name == raw) return ellipsoid;
    }
    return ReferenceEllipsoid.wgs84;
  }
}
