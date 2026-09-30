import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

final localeProvider = NotifierProvider<LocaleNotifier, Locale?>(
  LocaleNotifier.new,
);

class LocaleNotifier extends Notifier<Locale?> {
  static const _key = 'app_locale';

  @override
  Locale? build() {
    final raw = Hive.box('landbox').get(_key)?.toString();
    if (raw == null || raw.isEmpty || raw == 'system') return null;
    return Locale(raw);
  }

  Future<void> setLocale(Locale? locale) async {
    state = locale;
    final box = Hive.box('landbox');
    await box.put(_key, locale?.languageCode ?? 'system');
  }
}
