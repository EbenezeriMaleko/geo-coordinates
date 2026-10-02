import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taref_gps/core/localization/app_localizations.dart';

void main() {
  test('auth forms, verification, and errors localize', () {
    const french = AppLocalizations(Locale('fr'));
    const arabic = AppLocalizations(Locale('ar'));

    expect(french.t('Email is required'), 'L’adresse e-mail est obligatoire');
    expect(arabic.t('Email is required'), 'البريد الإلكتروني مطلوب');
    expect(french.t('Send Reset Link'), 'Envoyer le lien de réinitialisation');
    expect(arabic.t('Send Reset Link'), 'إرسال رابط إعادة التعيين');
    expect(
      french.t('Passwords do not match'),
      'Les mots de passe ne correspondent pas',
    );
    expect(arabic.t('Passwords do not match'), 'كلمتا المرور غير متطابقتين');
    expect(
      french.t(
        'Send a new verification email to {email}',
        params: {'email': 'test@example.com'},
      ),
      'Envoyer un nouvel e-mail de vérification à test@example.com',
    );
    expect(
      arabic.t(
        'Send a new verification email to {email}',
        params: {'email': 'test@example.com'},
      ),
      'إرسال رسالة تحقق جديدة إلى test@example.com',
    );
    expect(
      arabic.t('Login failed. Please try again.'),
      'فشل تسجيل الدخول. حاول مرة أخرى.',
    );
  });

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

  test('settings labels and parameterized messages localize', () {
    const english = AppLocalizations(Locale('en'));
    const french = AppLocalizations(Locale('fr'));
    const arabic = AppLocalizations(Locale('ar'));

    expect(english.t('Cloud synchronization'), 'Cloud synchronization');
    expect(french.t('Cloud synchronization'), 'Synchronisation cloud');
    expect(arabic.t('Cloud synchronization'), 'المزامنة السحابية');
    expect(french.t('Decimal Degrees'), 'Degrés décimaux');
    expect(arabic.t('Decimal Degrees'), 'درجات عشرية');
    expect(french.t('Arabic'), 'Arabe');
    expect(arabic.t('Other'), 'أخرى');
    expect(
      french.t(
        'Cache cleared successfully (~{size} MB freed)',
        params: {'size': '2.50'},
      ),
      'Cache vidé avec succès (environ 2.50 Mo libérés)',
    );
    expect(
      arabic.t('Coordinates now shown in {datum}', params: {'datum': 'WGS 84'}),
      'تُعرض الإحداثيات الآن وفق WGS 84',
    );
  });

  test('map controls and measurement messages localize', () {
    const french = AppLocalizations(Locale('fr'));
    const arabic = AppLocalizations(Locale('ar'));

    expect(
      french.t('Finding best route...'),
      'Recherche du meilleur itinéraire…',
    );
    expect(arabic.t('Finding best route...'), 'جارٍ البحث عن أفضل مسار…');
    expect(french.t('Square metres (m²)'), 'Mètres carrés (m²)');
    expect(arabic.t('Square metres (m²)'), 'متر مربع (م²)');
    expect(arabic.t('N'), 'شمال');
    expect(
      french.t(
        'Viewing: {name} · {count} pts',
        params: {'name': 'Farm', 'count': '3'},
      ),
      'Affichage : Farm · 3 pts',
    );
    expect(
      arabic.t('{count} points captured', params: {'count': '4'}),
      'النقاط الملتقطة: 4',
    );
  });

  test('my location, compass, and camera labels localize', () {
    const french = AppLocalizations(Locale('fr'));
    const arabic = AppLocalizations(Locale('ar'));

    expect(french.t('Compass'), 'Boussole');
    expect(arabic.t('Compass'), 'البوصلة');
    expect(french.compassAbbreviation('SW'), 'SO');
    expect(arabic.compassAbbreviation('NE'), 'ش ق');
    expect(french.t('North East'), 'Nord-est');
    expect(arabic.t('North East'), 'الشمال الشرقي');
    expect(arabic.t('Recent media'), 'الوسائط الحديثة');
    expect(arabic.t('Retake'), 'إعادة الالتقاط');
    expect(arabic.t('Photo saved to gallery'), 'تم حفظ الصورة في المعرض');
    expect(arabic.t('Camera permission is blocked'), 'إذن الكاميرا محظور');
    expect(
      french.t('Date {date}', params: {'date': '01/10/2026'}),
      'Date : 01/10/2026',
    );
    expect(
      arabic.t('Coordinates {coordinates}', params: {'coordinates': '1, 2'}),
      'الإحداثيات: 1, 2',
    );
  });

  test('media list and viewer labels localize', () {
    const french = AppLocalizations(Locale('fr'));
    const arabic = AppLocalizations(Locale('ar'));

    expect(
      french.t('Sign in to view uploaded media'),
      'Connectez-vous pour voir les médias téléversés',
    );
    expect(arabic.t('Location media'), 'وسائط الموقع');
    expect(
      arabic.t('No uploaded media found yet.'),
      'لم يُعثر على وسائط مرفوعة بعد.',
    );
    expect(arabic.t('Location ID'), 'معرّف الموقع');
    expect(french.t('Play'), 'Lire');
    expect(arabic.t('Pause'), 'إيقاف مؤقت');
  });

  test('saved-location labels and datum names localize', () {
    const french = AppLocalizations(Locale('fr'));
    const arabic = AppLocalizations(Locale('ar'));

    expect(french.t('No saved locations'), 'Aucun lieu enregistré');
    expect(arabic.t('No saved locations'), 'لا توجد مواقع محفوظة');
    expect(french.t('Arc 1960 — Tanzania'), 'Arc 1960 — Tanzanie');
    expect(arabic.t('Arc 1960 — Tanzania'), 'آرك 1960 — تنزانيا');
  });
}
