/// Combines the selected dialing code with the national subscriber number.
String? registrationPhoneNumber(
  String dialCode,
  String countryCode,
  String raw,
) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  if (countryCode == 'TZ' && digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  return '$dialCode$digits';
}
