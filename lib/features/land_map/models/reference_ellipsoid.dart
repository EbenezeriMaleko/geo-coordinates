enum ReferenceEllipsoid {
  clarke1866('Clarke 1866'),
  clarke1880('Clarke 1880'),
  grs1967('GRS 1967'),
  grs1980('GRS 1980'),
  wgs60('WGS 60'),
  wgs66('WGS 66'),
  wgs72('WGS 72'),
  wgs84('WGS 84');

  final String displayName;

  const ReferenceEllipsoid(this.displayName);

  bool get isDefault => this == ReferenceEllipsoid.wgs84;

  static ReferenceEllipsoid fromRaw(String? raw) {
    for (final ellipsoid in values) {
      if (ellipsoid.name == raw) return ellipsoid;
    }
    return ReferenceEllipsoid.wgs84;
  }
}
