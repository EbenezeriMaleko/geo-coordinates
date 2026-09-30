import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taref_gps/core/localization/app_localizations.dart';

void main() {
  test(
    'saved-location labels and parameters localize in supported languages',
    () {
      const english = AppLocalizations(Locale('en'));
      const french = AppLocalizations(Locale('fr'));
      const arabic = AppLocalizations(Locale('ar'));

      expect(english.t('Add manually'), 'Add manually');
    expect(french.t('Add manually'), 'Ajouter manuellement');
    expect(arabic.t('Add manually'), 'إضافة يدويًا');
    expect(french.t('Saved'), 'Enregistrés');
    expect(arabic.t('Saved'), 'المحفوظات');
      expect(
        arabic.t('No matching saved locations'),
        'لا توجد مواقع محفوظة مطابقة',
      );
      expect(french.t('General'), 'Général');

      expect(
        french.t('{count} results', params: {'count': '16'}),
        '16 résultats',
      );
      expect(
        arabic.t('Actions for {name}', params: {'name': 'Farm A'}),
        'إجراءات Farm A',
      );
      expect(
        french.t('Point {count} added.', params: {'count': '3'}),
        'Point 3 ajouté.',
      );
    },
  );
}
