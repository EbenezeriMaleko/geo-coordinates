import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:taref_gps/features/land_map/services/placemark_display.dart';

void main() {
  test('Plus Code is not presented as a street or address', () {
    const placemark = Placemark(
      street: '57V4+MP3',
      locality: 'Dar es Salaam',
      country: 'Tanzania',
    );

    expect(PlacemarkDisplay.street(placemark), isEmpty);
    expect(PlacemarkDisplay.place(placemark), 'Dar es Salaam');
    expect(PlacemarkDisplay.address(placemark), 'Dar es Salaam, Tanzania');
  });

  test('uses a real thoroughfare when street contains a Plus Code', () {
    const placemark = Placemark(
      street: '57V4+MP3, Dar es Salaam',
      thoroughfare: 'Pamba Street',
      locality: 'Dar es Salaam',
    );

    expect(PlacemarkDisplay.street(placemark), 'Pamba Street');
    expect(PlacemarkDisplay.address(placemark), 'Pamba Street, Dar es Salaam');
  });

  test('keeps a readable street address', () {
    const placemark = Placemark(
      street: '123 Pamba Street',
      locality: 'Dar es Salaam',
    );

    expect(PlacemarkDisplay.street(placemark), '123 Pamba Street');
  });

  test('does not label a standalone house number as a street', () {
    const placemark = Placemark(street: '123', locality: 'Dar es Salaam');

    expect(PlacemarkDisplay.street(placemark), isEmpty);
    expect(PlacemarkDisplay.place(placemark), 'Dar es Salaam');
  });
}
