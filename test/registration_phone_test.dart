import 'package:flutter_test/flutter_test.dart';
import 'package:taref_gps/features/auth/models/registration_phone.dart';

void main() {
  test('phone is optional', () {
    expect(registrationPhoneNumber('+255', 'TZ', ''), isNull);
  });
  test('Tanzanian trunk prefix is removed before adding country code', () {
    expect(
      registrationPhoneNumber('+255', 'TZ', '0712 345 678'),
      '+255712345678',
    );
    expect(registrationPhoneNumber('+255', 'TZ', '712345678'), '+255712345678');
  });
  test('other countries preserve the entered national digits', () {
    expect(registrationPhoneNumber('+39', 'IT', '0212345678'), '+390212345678');
  });
}
