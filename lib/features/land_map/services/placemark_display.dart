import 'package:geocoding/geocoding.dart';

/// Keeps geocoder fallback codes and house numbers out of the street label.
class PlacemarkDisplay {
  const PlacemarkDisplay._();

  static final _plusCode = RegExp(
    r'(^|[\s,])[23456789CFGHJMPQRVWX]{2,8}\+[23456789CFGHJMPQRVWX]{2,}(?=$|[\s,])',
    caseSensitive: false,
  );
  static final _numberOnly = RegExp(r'^[\d\s/#-]+$');

  static String street(Placemark? placemark) {
    if (placemark == null) return '';
    for (final value in [placemark.street, placemark.thoroughfare]) {
      final candidate = value?.trim() ?? '';
      if (_isReadable(candidate)) return candidate;
    }
    return '';
  }

  static String place(Placemark? placemark) {
    if (placemark == null) return '';
    final road = street(placemark);
    for (final value in [
      placemark.subLocality,
      placemark.locality,
      placemark.subAdministrativeArea,
      placemark.administrativeArea,
      placemark.country,
    ]) {
      final candidate = value?.trim() ?? '';
      if (_isReadable(candidate) &&
          candidate.toLowerCase() != road.toLowerCase()) {
        return candidate;
      }
    }
    return '';
  }

  static String address(Placemark? placemark) {
    if (placemark == null) return '';
    final values =
        <String>[
              street(placemark),
              placemark.subLocality ?? '',
              placemark.locality ?? '',
              placemark.administrativeArea ?? '',
              placemark.postalCode ?? '',
              placemark.country ?? '',
            ]
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty && !_plusCode.hasMatch(value))
            .toSet();
    return values.join(', ');
  }

  static bool _isReadable(String value) =>
      value.isNotEmpty &&
      !_plusCode.hasMatch(value) &&
      !_numberOnly.hasMatch(value) &&
      value.toLowerCase() != 'unnamed road';
}
