import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// App-localized strings for the languages currently supported by the app.
///
/// English is deliberately the source language. If a key has not been
/// translated yet, the English value is returned so new screens never show a
/// blank label while translations are being added.
class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr'),
    Locale('ar'),
  ];

  static const delegate = _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    final value = Localizations.of<AppLocalizations>(context, AppLocalizations);
    assert(value != null, 'AppLocalizations is not installed on MaterialApp');
    return value!;
  }

  bool get isFrench => locale.languageCode == 'fr';
  bool get isArabic => locale.languageCode == 'ar';

  String t(String english, {Map<String, String> params = const {}}) {
    var translated = isArabic
        ? _ar[english] ?? english
        : isFrench
        ? _fr[english] ?? english
        : english;
    for (final entry in params.entries) {
      translated = translated.replaceAll('{${entry.key}}', entry.value);
    }
    return translated;
  }

  String compassAbbreviation(String direction) {
    if (isFrench) {
      return const {'W': 'O', 'SW': 'SO', 'NW': 'NO'}[direction] ?? direction;
    }
    if (isArabic) {
      return const {
            'N': 'ش',
            'NE': 'ش ق',
            'E': 'ق',
            'SE': 'ج ق',
            'S': 'ج',
            'SW': 'ج غ',
            'W': 'غ',
            'NW': 'ش غ',
          }[direction] ??
          direction;
    }
    return direction;
  }

  String copied(String label) => isArabic
      ? 'تم نسخ $label'
      : isFrench
      ? '$label copié'
      : '$label copied';

  String uploaded(String mediaType) => isArabic
      ? 'تم رفع $mediaType إلى السحابة'
      : isFrench
      ? '$mediaType téléversé vers le cloud'
      : '$mediaType uploaded to cloud';

  String savedLocally(String error) => isArabic
      ? 'تم الحفظ محليًا: $error'
      : isFrench
      ? 'Enregistré localement : $error'
      : 'Saved locally: $error';

  String satisfaction(int score) => isArabic
      ? 'التقييم: $score من 5'
      : isFrench
      ? 'Satisfaction : $score sur 5'
      : 'Satisfaction $score out of 5';

  static const _fr = <String, String>{
    'Required': 'Obligatoire',
    'Enter a valid email': 'Saisissez une adresse e-mail valide',
    'Password is required': 'Le mot de passe est obligatoire',
    'Password must be at least 6 characters':
        'Le mot de passe doit contenir au moins 6 caractères',
    "Don't have an account? ": 'Vous n’avez pas de compte ? ',
    'Send Reset Link': 'Envoyer le lien de réinitialisation',
    'Remembered your password? ': 'Vous vous souvenez de votre mot de passe ? ',
    'Token is required': 'Le jeton est obligatoire',
    'Confirm your password': 'Confirmez votre mot de passe',
    'Must include uppercase & number':
        'Doit contenir une majuscule et un chiffre',
    'Please confirm your password': 'Veuillez confirmer votre mot de passe',
    'I agree to the ': 'J’accepte les ',
    'Terms and Conditions': 'conditions générales',
    'You must accept the terms to continue.':
        'Vous devez accepter les conditions pour continuer.',
    'Send a new verification email to {email}':
        'Envoyer un nouvel e-mail de vérification à {email}',
    'Email not verified': 'Adresse e-mail non vérifiée',
    'A verification code will be sent to your email address. The request is throttled to 3 times per minute.':
        'Un code de vérification sera envoyé à votre adresse e-mail. Vous pouvez faire 3 demandes par minute.',
    'The confirm request is throttled to 6 times per minute.':
        'Vous pouvez confirmer jusqu’à 6 fois par minute.',
    'Login failed. Please try again.': 'Échec de la connexion. Réessayez.',
    'Registration failed. Please try again.':
        'Échec de l’inscription. Réessayez.',
    'Failed to request password reset.':
        'Impossible de demander la réinitialisation du mot de passe.',
    'Failed to reset password.': 'Impossible de réinitialiser le mot de passe.',
    'Failed to update profile.': 'Impossible de mettre à jour le profil.',
    'Failed to update password.':
        'Impossible de mettre à jour le mot de passe.',
    'Failed to send verification email.':
        'Impossible d’envoyer l’e-mail de vérification.',
    'Failed to request account deletion.':
        'Impossible de demander la suppression du compte.',
    'Failed to confirm account deletion.':
        'Impossible de confirmer la suppression du compte.',
    'Unable to connect. Check your internet connection.':
        'Connexion impossible. Vérifiez votre connexion Internet.',
    'Land Mapper': 'Cartographie des terres',
    'Settings': 'Paramètres',
    'Account': 'Compte',
    'Sign In': 'Se connecter',
    'Sign in': 'Se connecter',
    'Sign out': 'Se déconnecter',
    'Logout': 'Déconnexion',
    'Create account': 'Créer un compte',
    'Connect this device to your cloud account':
        'Connecter cet appareil à votre compte cloud',
    'Register a new account for sync access':
        'Créer un compte pour accéder à la synchronisation',
    'Request password reset by email':
        'Demander la réinitialisation du mot de passe par e-mail',
    'Profile': 'Profil',
    'Edit name, email and phone number':
        'Modifier le nom, l’e-mail et le numéro de téléphone',
    'Update your account password': 'Modifier le mot de passe de votre compte',
    'Open TaREF web app': 'Ouvrir l’application web TaREF',
    'Manage your data at ardhi.co.tz': 'Gérer vos données sur ardhi.co.tz',
    'Verification': 'Vérification',
    'Resend verification email': 'Renvoyer l’e-mail de vérification',
    'Session': 'Session',
    'Stop cloud sync on this device and keep local data':
        'Arrêter la synchronisation cloud sur cet appareil et conserver les données locales',
    'Danger zone': 'Zone dangereuse',
    'Permanently delete your account. You will need your password and email access to confirm.':
        'Supprimez définitivement votre compte. Votre mot de passe et l’accès à votre e-mail seront nécessaires pour confirmer.',
    'Enter the reset token from email and choose a new password.':
        'Saisissez le jeton reçu par e-mail et choisissez un nouveau mot de passe.',
    'Reset token': 'Jeton de réinitialisation',
    'Register': 'S’inscrire',
    'Forgot password': 'Mot de passe oublié',
    'Forgot password?': 'Mot de passe oublié ?',
    'Change password': 'Modifier le mot de passe',
    'Change Password': 'Modifier le mot de passe',
    'Reset Password': 'Réinitialiser le mot de passe',
    'Enter your email to receive a reset link':
        'Saisissez votre e-mail pour recevoir un lien de réinitialisation',
    'Could not open terms and conditions':
        'Impossible d’ouvrir les conditions générales',
    'Account Created!': 'Compte créé !',
    'Sign In Now': 'Se connecter maintenant',
    'Create Account': 'Créer un compte',
    'Join Taref Gps today': 'Rejoignez Taref GPS aujourd’hui',
    'First Name': 'Prénom',
    'Last Name': 'Nom',
    'Confirm Password': 'Confirmer le mot de passe',
    'Already have an account? ': 'Vous avez déjà un compte ? ',
    'Reset password': 'Réinitialiser le mot de passe',
    'Update Profile': 'Modifier le profil',
    'Update profile': 'Modifier le profil',
    'Profile updated successfully': 'Profil mis à jour avec succès',
    'Save changes': 'Enregistrer les modifications',
    'Cancel': 'Annuler',
    'Save': 'Enregistrer',
    'Delete': 'Supprimer',
    'Delete account': 'Supprimer le compte',
    'Delete account?': 'Supprimer le compte ?',
    'Delete marker': 'Supprimer le repère',
    'Back': 'Retour',
    'Close': 'Fermer',
    'Done': 'Terminé',
    'Enable': 'Activer',
    'Grant Permission': 'Accorder l’autorisation',
    'Open Settings': 'Ouvrir les paramètres',
    'Cloud synchronization': 'Synchronisation cloud',
    'Signed in': 'Connecté',
    'Sign in only when you want to sync data to the server.':
        'Connectez-vous uniquement lorsque vous souhaitez synchroniser les données avec le serveur.',
    'Location Settings': 'Paramètres de localisation',
    'Coordinates format': 'Format des coordonnées',
    'Decimal Degrees': 'Degrés décimaux',
    'Degrees Minutes Seconds': 'Degrés minutes secondes',
    'Degrees Decimal Minutes': 'Degrés minutes décimales',
    'Example: {coordinates}': 'Exemple : {coordinates}',
    'Minna — Nigeria': 'Minna — Nigeria',
    'Arc 1960 — Kenya/Tanzania mean': 'Arc 1960 — moyenne Kenya/Tanzanie',
    'Arc 1960 — Kenya': 'Arc 1960 — Kenya',
    'Arc 1960 — Tanzania': 'Arc 1960 — Tanzanie',
    'Arc 1950 — Southern Africa mean': 'Arc 1950 — moyenne Afrique australe',
    'NAD27 — CONUS': 'NAD27 — États-Unis contigus',
    'NAD83 — North America': 'NAD83 — Amérique du Nord',
    'ETRS89 — Europe': 'ETRS89 — Europe',
    'GDA94 — Australia': 'GDA94 — Australie',
    'SAD69 — South America mean': 'SAD69 — moyenne Amérique du Sud',
    'WGS 72 — global': 'WGS 72 — mondial',
    'Nigeria — onshore and offshore': 'Nigeria — terrestre et maritime',
    'Kenya and Tanzania': 'Kenya et Tanzanie',
    'Kenya — onshore': 'Kenya — terrestre',
    'Tanzania — onshore': 'Tanzanie — terrestre',
    'Botswana, Eswatini, Lesotho, Malawi, Zambia and Zimbabwe':
        'Botswana, Eswatini, Lesotho, Malawi, Zambie et Zimbabwe',
    'Contiguous United States — onshore': 'États-Unis contigus — terrestre',
    'North America': 'Amérique du Nord',
    'Europe — onshore and offshore': 'Europe — terrestre et maritime',
    'Australia and external territories': 'Australie et territoires extérieurs',
    'South America onshore north of 45°S, excluding Amazonia':
        'Amérique du Sud terrestre au nord de 45° S, hors Amazonie',
    'World': 'Monde',
    'Geodetic datum': 'Datum géodésique',
    'Select datum': 'Choisir un datum',
    'Choose the datum used by your survey. Its reference ellipsoid is shown below the datum name.':
        'Choisissez le datum utilisé pour votre levé. Son ellipsoïde de référence figure sous son nom.',
    'WGS 84 ellipsoid • Global reference system (default; valid everywhere)':
        'Ellipsoïde WGS 84 • Système de référence mondial (par défaut ; valable partout)',
    '{ellipsoid} ellipsoid • {area}\nEPSG:{code} • {accuracy} m accuracy':
        'Ellipsoïde {ellipsoid} • {area}\nEPSG:{code} • précision de {accuracy} m',
    ' • Approximate': ' • Approximatif',
    ' • Valid here': ' • Valable ici',
    'REFERENCE / ELLIPSOID-ONLY OPTIONS':
        'OPTIONS DE RÉFÉRENCE / ELLIPSOÏDE SEUL',
    '{ellipsoid} ellipsoid • No verified datum transformation; ellipsoid-shape-only conversion':
        'Ellipsoïde {ellipsoid} • Aucune transformation de datum vérifiée ; conversion de forme de l’ellipsoïde uniquement',
    'Coordinates now shown in {datum}':
        'Coordonnées maintenant affichées en {datum}',
    'Error changing coordinate display: {error}':
        'Erreur lors du changement d’affichage des coordonnées : {error}',
    'Compass north reference': 'Référence du nord de la boussole',
    'True North (geographic)': 'Nord géographique',
    'Units': 'Unités',
    'Meters': 'Mètres',
    'Feet': 'Pieds',
    'Use meters (m)': 'Utiliser les mètres (m)',
    'Use feet (ft)': 'Utiliser les pieds (pi)',
    'Magnetic North': 'Nord magnétique',
    'True North': 'Nord géographique',
    'Uses raw compass sensor reading. No correction applied.':
        'Utilise la lecture brute du capteur de boussole. Aucune correction appliquée.',
    'Corrects for magnetic declination to point to geographic north.':
        'Corrige la déclinaison magnétique pour pointer vers le nord géographique.',
    'Photo': 'Photo',
    'Save original photo': 'Enregistrer la photo originale',
    'Save with no data on it. Useful for editing before sharing.':
        'Enregistrer sans données incrustées. Utile pour retoucher la photo avant de la partager.',
    'Save to gallery': 'Enregistrer dans la galerie',
    'Save image with data': 'Enregistrer l’image avec les données',
    'Privacy policy': 'Politique de confidentialité',
    'Cache': 'Cache',
    'Clear cache': 'Vider le cache',
    'Clear cache?': 'Vider le cache ?',
    'Remove cached data and temporary files':
        'Supprimer les données en cache et les fichiers temporaires',
    'Cache cleared successfully': 'Cache vidé avec succès',
    'Cache cleared successfully (~{size} MB freed)':
        'Cache vidé avec succès (environ {size} Mo libérés)',
    'Error clearing cache: {error}': 'Erreur lors du vidage du cache : {error}',
    'This will clear all cached data including images, temporary files, and app cache storage. Your saved locations will not be affected.':
        'Toutes les données en cache, images et fichiers temporaires seront supprimés. Vos lieux enregistrés ne seront pas affectés.',
    'Preview ready. Open Library. Submitting the form sends a real response.':
        'Aperçu prêt. Ouvrez la bibliothèque. L’envoi du formulaire transmettra une vraie réponse.',
    'Information': 'Informations',
    'Contact us': 'Nous contacter',
    'Send suggestions or report a bug. We appreciate your feedback.':
        'Envoyez vos suggestions ou signalez un bug. Votre avis nous est précieux.',
    'Send feedback': 'Envoyer un avis',
    '[TaREF GPS] Feedback': '[TaREF GPS] Avis',
    'We read every message': 'Nous lisons chaque message',
    'Tell us what\'s on your mind — a bug, suggestion, or question…':
        'Parlez-nous d’un bug, d’une suggestion ou d’une question…',
    'Send': 'Envoyer',
    'No email app found. Message copied — send it to {email}':
        'Aucune application e-mail trouvée. Message copié — envoyez-le à {email}',
    'Device': 'Appareil',
    'Product': 'Produit',
    'Model': 'Modèle',
    'App version': 'Version de l’application',
    'Platform': 'Plateforme',
    'Share your experience': 'Partager votre expérience',
    'Tell us what works and what is difficult.':
        'Dites-nous ce qui fonctionne et ce qui est difficile.',
    'Preview survey invitation': 'Prévisualiser l’invitation à l’enquête',
    'Debug only. Open Library after tapping.':
        'Débogage uniquement. Ouvrez la bibliothèque après avoir appuyé.',
    'Rate our app': 'Évaluer notre application',
    'Leave a rating or review in the app store.':
        'Laissez une note ou un avis dans la boutique d’applications.',
    'Version': 'Version',
    'Loading version...': 'Chargement de la version…',
    'Version unavailable': 'Version indisponible',
    'Reading build metadata from the app package...':
        'Lecture des informations de version de l’application…',
    'This comes from the installed app metadata.':
        'Ces informations proviennent de l’application installée.',
    'Language': 'Langue',
    'System default': 'Langue du système',
    'English': 'Anglais',
    'French': 'Français',
    'Arabic': 'Arabe',
    'Map': 'Carte',
    'Map Type': 'Type de carte',
    'Normal': 'Normale',
    'Satellite': 'Satellite',
    'Terrain': 'Terrain',
    'Hybrid': 'Hybride',
    'Layers': 'Couches',
    'Field': 'Terrain',
    'My location': 'Ma position',
    'My Location': 'Ma position',
    'Compass accuracy': 'Précision de la boussole',
    'UTM Zone': 'Zone UTM',
    'Easting': 'Est',
    'Northing': 'Nord',
    'Altitude': 'Altitude',
    'Accuracy': 'Précision',
    'Signal': 'Signal',
    'Location age': 'Âge de la position',
    'Tracking': 'Suivi',
    'Speed': 'Vitesse',
    'Lat/Lon': 'Lat/Long',
    'UTM': 'UTM',
    'Motion': 'Mouvement',
    'Heading': 'Direction',
    'Reference': 'Référence',
    'Display datum': 'Datum affiché',
    'Captured at': 'Capturé le',
    'Location note': 'Note de position',
    'EASTING': 'EST',
    'NORTHING': 'NORD',
    'Zone': 'Zone',
    'Format': 'Format',
    'Datum': 'Datum',
    'Updated': 'Mis à jour',
    'Live location is unavailable': 'La position en direct est indisponible',
    'Live coordinates and GPS tracking are off. Other app features remain available.':
        'Les coordonnées en direct et le suivi GPS sont désactivés. Les autres fonctions restent disponibles.',
    'Enable live location?': 'Activer la localisation en direct ?',
    'TaREF GPS needs Location Services to display live coordinates, track your position, save GPS points, support navigation, and geotag captured photos or videos. You can continue using other app features without live location.':
        'TaREF GPS a besoin des services de localisation pour afficher les coordonnées en direct, suivre votre position, enregistrer des points GPS, faciliter la navigation et géolocaliser les photos ou vidéos. Vous pouvez continuer à utiliser les autres fonctions sans localisation en direct.',
    'Location access is blocked for TaREF GPS. Enable it in Settings to display live coordinates, save your current position, support navigation, and geotag media. You can continue using the app without live GPS.':
        'L’accès à la localisation est bloqué pour TaREF GPS. Activez-le dans les paramètres pour afficher les coordonnées en direct, enregistrer votre position, utiliser la navigation et géolocaliser les médias. Vous pouvez continuer à utiliser l’application sans GPS en direct.',
    'TaREF GPS uses your current location only for GPS features such as live coordinates, position tracking, saved points, navigation, and automatic photo or video geotagging. Other app features remain available without it.':
        'TaREF GPS utilise votre position uniquement pour les fonctions GPS, comme les coordonnées en direct, le suivi, les points enregistrés, la navigation et la géolocalisation des photos ou vidéos. Les autres fonctions restent disponibles sans localisation.',
    'System camera mode is not available yet, using in-app camera.':
        'Le mode appareil photo système n’est pas encore disponible ; utilisation de l’appareil photo intégré.',
    'Location tracking is active': 'Le suivi de la position est actif',
    'TaREF GPS - Coordinates': 'TaREF GPS - Coordonnées',
    'Coordinates unavailable': 'Coordonnées indisponibles',
    'Video deleted': 'Vidéo supprimée',
    'Photo deleted': 'Photo supprimée',
    'GPS Camera': 'Appareil photo GPS',
    'GPS Capture': 'Capture GPS',
    'Preview': 'Aperçu',
    'Camera permission is denied. Allow camera permission in app settings.':
        'L’accès à l’appareil photo est refusé. Autorisez-le dans les paramètres de l’application.',
    'Failed to open camera. Please try again.':
        'Impossible d’ouvrir l’appareil photo. Veuillez réessayer.',
    '{media} saved locally. Cloud upload failed.':
        '{media} enregistré localement. L’envoi vers le cloud a échoué.',
    'Video': 'Vidéo',
    'Good': 'Bonne',
    'Fair': 'Moyenne',
    'Poor': 'Faible',
    'Compass': 'Boussole',
    'Unavailable': 'Indisponible',
    'North': 'Nord',
    'North East': 'Nord-est',
    'East': 'Est',
    'South East': 'Sud-est',
    'South': 'Sud',
    'South West': 'Sud-ouest',
    'West': 'Ouest',
    'North West': 'Nord-ouest',
    'Magnetic': 'Magnétique',
    'Not reported': 'Non indiqué',
    'High': 'Élevée',
    'Moderate': 'Modérée',
    'Low': 'Faible',
    'Compass sensor unavailable on this device.':
        'Capteur de boussole indisponible sur cet appareil.',
    'Live compass · {north}': 'Boussole en direct · {north}',
    'Location permission is required for the compass sensor on Android.':
        'L’autorisation de localisation est nécessaire pour utiliser la boussole sur Android.',
    'Initializing GPS…': 'Initialisation du GPS…',
    'Live tracking': 'Suivi en direct',
    'Tracking paused': 'Suivi en pause',
    'GPS media details': 'Détails du média GPS',
    'UTM unavailable for this latitude': 'UTM indisponible à cette latitude',
    'Camera permission is blocked': 'Accès à l’appareil photo bloqué',
    'Camera permission is required': 'Autorisation de l’appareil photo requise',
    'Failed to initialize the camera':
        'Impossible d’initialiser l’appareil photo',
    'Open app settings and allow camera access to take GPS photos.':
        'Ouvrez les paramètres de l’application et autorisez l’appareil photo pour prendre des photos GPS.',
    'Grant camera permission to capture GPS-tagged photos and videos.':
        'Autorisez l’appareil photo pour capturer des photos et vidéos géolocalisées.',
    'Something went wrong. Try again or check your device camera.':
        'Une erreur est survenue. Réessayez ou vérifiez l’appareil photo de votre appareil.',
    'Try Again': 'Réessayer',
    'Location service is disabled.':
        'Le service de localisation est désactivé.',
    'Location is off. Media will be saved without a GPS tag.':
        'La localisation est désactivée. Le média sera enregistré sans position GPS.',
    'Unable to resolve current location.':
        'Impossible de déterminer la position actuelle.',
    'Live location updates failed.':
        'Échec de la mise à jour de la position en direct.',
    'Recording… Tap to stop': 'Enregistrement… Appuyez pour arrêter',
    'Tap to record video': 'Appuyez pour enregistrer une vidéo',
    'Tap to capture photo': 'Appuyez pour prendre une photo',
    'Recent media': 'Médias récents',
    'No local media yet': 'Aucun média local pour le moment',
    'No photos captured yet': 'Aucune photo prise pour le moment',
    'Tap to view cloud media': 'Appuyez pour voir les médias du cloud',
    'Tap to capture your first photo':
        'Appuyez pour prendre votre première photo',
    'Date {date}': 'Date : {date}',
    'Street {street}': 'Rue : {street}',
    'Place {place}': 'Lieu : {place}',
    'Coordinates {coordinates}': 'Coordonnées : {coordinates}',
    'Accuracy {accuracy}': 'Précision : {accuracy}',
    'Waiting for GPS details': 'En attente des données GPS',
    'Address unavailable': 'Adresse indisponible',
    'Saved locations': 'Lieux enregistrés',
    'Location': 'Position',
    'Coordinates': 'Coordonnées',
    'Address': 'Adresse',
    'Phone': 'Téléphone',
    'Email': 'E-mail',
    'System': 'Système',
    'All': 'Tous',
    'Images': 'Images',
    'Videos': 'Vidéos',
    'Copy coordinates': 'Copier les coordonnées',
    'Share location': 'Partager la position',
    'Save location': 'Enregistrer la position',
    'Place name': 'Nom du lieu',
    'Enter place name': 'Saisissez le nom du lieu',
    'Skip': 'Ignorer',
    'Update Area': 'Modifier la surface',
    'Create Area': 'Créer une surface',
    'Capture boundary points and save your land details.':
        'Capturez les points de la limite et enregistrez les détails de votre terrain.',
    'Place *': 'Lieu *',
    'Phone (optional)': 'Téléphone (facultatif)',
    'Add notes about this land': 'Ajoutez des notes sur ce terrain',
    'Boundary capture': 'Capture de la limite',
    'Mark current Location while walking around the field boundary.':
        'Marquez votre position actuelle en parcourant la limite du terrain.',
    'Mark Current Location': 'Marquer la position actuelle',
    'Undo Last': 'Annuler le dernier',
    'Clear All': 'Tout effacer',
    'Choose area display unit': 'Choisir l’unité de surface',
    'Save Distance': 'Enregistrer la distance',
    'Store this measured line locally and send it to the server as a distance record.':
        'Enregistrez cette ligne mesurée localement et envoyez-la au serveur comme distance.',
    'Contact phone': 'Téléphone de contact',
    'Notes about this distance': 'Notes sur cette distance',
    'Point labels': 'Étiquettes des points',
    'Point': 'Point',
    'Place is required.': 'Le lieu est obligatoire.',
    'Save distance': 'Enregistrer la distance',
    'Add location name and point label before saving.':
        'Ajoutez un nom de lieu et une étiquette de point avant d’enregistrer.',
    'e.g. Home, Office, Farm Entrace': 'ex. Maison, bureau, entrée du terrain',
    'Point label (e.g. A1, P1)': 'Étiquette du point (ex. A1, P1)',
    'Center here': 'Centrer ici',
    'View area in': 'Afficher la surface en',
    'Description (optional)': 'Description (facultative)',
    'e.g. 0712345678': 'p. ex. 0712345678',
    'Point added': 'Point ajouté',
    '{count} points captured': '{count} points capturés',
    'Perimeter: {distance}': 'Périmètre : {distance}',
    'Area: {area}': 'Surface : {area}',
    'Optional. Rename boundary points for reference.':
        'Facultatif. Renommez les points de limite pour les retrouver.',
    'Point {number}': 'Point {number}',
    'Label': 'Étiquette',
    'Field updated offline successfully. Sync queued.':
        'Terrain modifié hors ligne. Synchronisation en attente.',
    'Field saved offline successfully. Sync queued.':
        'Terrain enregistré hors ligne. Synchronisation en attente.',
    'Save Area': 'Enregistrer la surface',
    'Distance name or place': 'Nom ou lieu de la distance',
    '{count} points • {distance}': '{count} points • {distance}',
    'Automatic': 'Automatique',
    'Square metres (m²)': 'Mètres carrés (m²)',
    'Hectares (ha)': 'Hectares (ha)',
    'Square kilometres (km²)': 'Kilomètres carrés (km²)',
    'Square feet (ft²)': 'Pieds carrés (ft²)',
    'Acres (ac)': 'Acres (ac)',
    'Long-press map to add points':
        'Maintenez la carte appuyée pour ajouter des points',
    '{count} pts · {distance}': '{count} pts · {distance}',
    'Long-press map to place marker':
        'Maintenez la carte appuyée pour placer un repère',
    'Long-press map or use + GPS to add area points':
        'Maintenez la carte appuyée ou utilisez + GPS pour ajouter des points de surface',
    '{count} area pts · long-press to add more':
        '{count} points de surface · maintenez appuyé pour en ajouter',
    'Location saved locally. Sync queued.':
        'Position enregistrée localement. Synchronisation en attente.',
    'No current location available.': 'Aucune position actuelle disponible.',
    'Marker deleted': 'Repère supprimé',
    'Add at least 2 points to save a distance.':
        'Ajoutez au moins 2 points pour enregistrer une distance.',
    'Distance saved locally. Sync queued.':
        'Distance enregistrée localement. Synchronisation en attente.',
    'Road routing unavailable. Showing straight line.':
        'Itinéraire routier indisponible. Affichage d’une ligne droite.',
    'Route updated from your current position.':
        'Itinéraire mis à jour depuis votre position actuelle.',
    'Turn on the Field layer to add area points.':
        'Activez la couche Terrain pour ajouter des points de surface.',
    'Finding best route...': 'Recherche du meilleur itinéraire…',
    'Switching map type...': 'Changement du type de carte…',
    'UTM unavailable': 'UTM indisponible',
    '{reference} • Accuracy: {accuracy}':
        '{reference} • Précision : {accuracy}',
    'Locating...': 'Localisation en cours…',
    'Waiting for GPS...': 'En attente du GPS…',
    '{count} pts': '{count} pts',
    'Calculating...': 'Calcul en cours…',
    'Viewing: {name} · {count} pts': 'Affichage : {name} · {count} pts',
    'Tools': 'Outils',
    'Location Services are off': 'Les services de localisation sont désactivés',
    'Location unavailable': 'Position indisponible',
    'Use your current location?': 'Utiliser votre position actuelle ?',
    'TaREF GPS needs Location Services to show your live position on the map, capture GPS points, guide navigation, measure routes, and attach coordinates to saved work. You can continue using the map and saved records without live GPS.':
        'TaREF GPS a besoin des services de localisation pour afficher votre position en direct sur la carte, capturer des points GPS, guider la navigation, mesurer des itinéraires et joindre des coordonnées aux données enregistrées. Vous pouvez continuer à utiliser la carte et vos données enregistrées sans GPS en direct.',
    'Location access is blocked for TaREF GPS. Enable it in Settings to use live map position, GPS point capture, navigation guidance, route measurement, and coordinate tagging. You can continue using the app without GPS.':
        'L’accès à la localisation est bloqué pour TaREF GPS. Activez-le dans les paramètres pour utiliser la position en direct, la capture de points GPS, la navigation, la mesure d’itinéraires et l’ajout de coordonnées. Vous pouvez continuer à utiliser l’application sans GPS.',
    'TaREF GPS uses your current location only for GPS features such as live map position, point capture, navigation, distance tracking, and coordinate tagging. You can continue using the map without granting location access.':
        'TaREF GPS utilise votre position actuelle uniquement pour les fonctions GPS telles que la position en direct, la capture de points, la navigation, le suivi des distances et l’ajout de coordonnées. Vous pouvez continuer à utiliser la carte sans autoriser l’accès à votre position.',
    '+ GPS': '+ GPS',
    'Long-press the map to add area points, or use + GPS for your current location.':
        'Maintenez la carte appuyée pour ajouter des points de surface, ou utilisez + GPS pour votre position actuelle.',
    'Save area': 'Enregistrer la surface',
    'Long-press anywhere on the map to place a marker':
        'Maintenez n’importe quelle zone de la carte appuyée pour placer un repère',
    'Location saved': 'Position enregistrée',
    'Enter location name (optional)': 'Saisissez le nom du lieu (facultatif)',
    'Could not open email app': 'Impossible d’ouvrir l’application e-mail',
    'Could not open phone app': 'Impossible d’ouvrir l’application téléphone',
    'Location refreshed': 'Position actualisée',
    'Location not available yet': 'Position pas encore disponible',
    'Search saved locations': 'Rechercher des lieux enregistrés',
    'Search': 'Rechercher',
    'All saved lands': 'Tous les terrains enregistrés',
    '3+ points only': '3 points ou plus uniquement',
    'Updated only': 'Mis à jour uniquement',
    'Newest first': 'Les plus récents en premier',
    'Oldest first': 'Les plus anciens en premier',
    'Name A-Z': 'Nom A-Z',
    'Name Z-A': 'Nom Z-A',
    'Most points': 'Le plus de points',
    'Select multiple': 'Sélectionner plusieurs',
    'Reset filters/sort/group':
        'Réinitialiser les filtres, le tri et le groupe',
    'Delete all saved lands': 'Supprimer tous les terrains enregistrés',
    'Delete all saved lands?': 'Supprimer tous les terrains enregistrés ?',
    'Markers will be kept. This action cannot be undone.':
        'Les repères seront conservés. Cette action est irréversible.',
    'Delete all': 'Tout supprimer',
    'Nothing to share': 'Rien à partager',
    'Selected items shared': 'Éléments sélectionnés partagés',
    'Delete selected locations?': 'Supprimer les lieux sélectionnés ?',
    'Sign in again to delete cloud records.':
        'Reconnectez-vous pour supprimer les données cloud.',
    'Set group for selected': 'Définir le groupe pour la sélection',
    'Group name': 'Nom du groupe',
    'Group updated for selected items':
        'Groupe mis à jour pour les éléments sélectionnés',
    'Add location manually': 'Ajouter un lieu manuellement',
    'Enter coordinates in your preferred format':
        'Saisissez les coordonnées dans votre format préféré',
    'Location details': 'Détails du lieu',
    'Name *': 'Nom *',
    'e.g. Farm boundary, Warehouse': 'ex. Limite de terrain, entrepôt',
    'e.g. Dodoma, Tanzania': 'ex. Dodoma, Tanzanie',
    'Contact number': 'Numéro de contact',
    'Notes about this location': 'Notes sur ce lieu',
    'Record type': 'Type d’enregistrement',
    'Auto': 'Automatique',
    'Type is determined by point count: 1 = Point, 2 = Distance, 3+ = Area':
        'Le type dépend du nombre de points : 1 = point, 2 = distance, 3+ = surface',
    'Add coordinate points': 'Ajouter des points de coordonnées',
    'Choose your preferred coordinate format to add points one by one.':
        'Choisissez votre format de coordonnées préféré pour ajouter les points un par un.',
    'Added points': 'Points ajoutés',
    'Latitude': 'Latitude',
    'Longitude': 'Longitude',
    'Point label (optional)': 'Étiquette du point (facultatif)',
    'e.g. A1, Corner 1': 'ex. A1, coin 1',
    'Add point': 'Ajouter un point',
    'Zone number': 'Numéro de zone',
    'Band letter': 'Lettre de bande',
    'Hemisphere': 'Hémisphère',
    'Go to': 'Aller à',
    'Go to map': 'Aller à la carte',
    'View on map': 'Voir sur la carte',
    'View details': 'Voir les détails',
    'Edit metadata': 'Modifier les métadonnées',
    'Rename': 'Renommer',
    'Share': 'Partager',
    'Refresh': 'Actualiser',
    'Deleting...': 'Suppression…',
    'Delete land': 'Supprimer le terrain',
    'Coordinates copied': 'Coordonnées copiées',
    'Rename location': 'Renommer le lieu',
    'Name': 'Nom',
    'Delete location?': 'Supprimer le lieu ?',
    'This action cannot be undone.': 'Cette action est irréversible.',
    'No points found for guidance': 'Aucun point trouvé pour le guidage',
    'No points to display on map': 'Aucun point à afficher sur la carte',
    'No cloud ID found for this record.':
        'Aucun identifiant cloud trouvé pour cet enregistrement.',
    'Sign in required to load cloud coordinates.':
        'Connectez-vous pour charger les coordonnées cloud.',
    'Loading coordinates…': 'Chargement des coordonnées…',
    'This record has no coordinates available.':
        'Cet enregistrement ne contient aucune coordonnée disponible.',
    'Changes saved. They will sync when connected.':
        'Modifications enregistrées. Elles seront synchronisées lorsque la connexion sera disponible.',
    'Edit cloud land': 'Modifier le terrain cloud',
    'Details': 'Détails',
    'Type': 'Type',
    'Created': 'Créé le',
    'Delete cloud land?': 'Supprimer le terrain cloud ?',
    'Land deleted from cloud': 'Terrain supprimé du cloud',
    'Land deleted from cloud and app':
        'Terrain supprimé du cloud et de l’application',
    'Retry': 'Réessayer',
    'selected': 'sélectionnés',
    'Set group': 'Définir le groupe',
    'Share selected': 'Partager la sélection',
    'Delete selected': 'Supprimer la sélection',
    'Exit selection': 'Quitter la sélection',
    'Help us improve TaREF': 'Aidez-nous à améliorer TaREF',
    'Not now': 'Pas maintenant',
    'Tell us what is working and what is difficult. It takes about a minute.':
        'Dites-nous ce qui fonctionne et ce qui est difficile. Cela prend environ une minute.',
    'Share feedback': 'Partager un commentaire',
    'Group': 'Groupe',
    'Route': 'Itinéraire',
    'result': 'résultat',
    'results': 'résultats',
    'Showing latest records. Use the web app to view older records.':
        'Affichage des enregistrements récents. Utilisez l’application web pour voir les anciens enregistrements.',
    'Please answer the three required questions.':
        'Veuillez répondre aux trois questions obligatoires.',
    'Could not save your response. Try again.':
        'Impossible d’enregistrer votre réponse. Réessayez.',
    'What is your role? *': 'Quel est votre rôle ? *',
    'Select your role': 'Sélectionnez votre rôle',
    'What is most difficult? *': 'Quelle est la principale difficulté ? *',
    'Choose one area': 'Choisissez un domaine',
    'Overall, how satisfied are you? *':
        'Globalement, quel est votre niveau de satisfaction ? *',
    'Very dissatisfied': 'Très insatisfait',
    'Very satisfied': 'Très satisfait',
    'Anything else? (optional)': 'Autre chose ? (facultatif)',
    'Tell us more about your experience':
        'Parlez-nous davantage de votre expérience',
    'Optional survey. No coordinates or saved records are collected. Your response stays on this device until it can be sent. We will retry automatically when the server is available.':
        'Enquête facultative. Aucune coordonnée ni donnée enregistrée n’est collectée. Votre réponse reste sur cet appareil jusqu’à son envoi. Nous réessaierons automatiquement lorsque le serveur sera disponible.',
    'Saving…': 'Enregistrement…',
    'Save response': 'Enregistrer la réponse',
    'Surveyor': 'Géomètre',
    'Engineer': 'Ingénieur',
    'Land professional': 'Professionnel du foncier',
    'Researcher': 'Chercheur',
    'Other': 'Autre',
    'GPS accuracy': 'Précision GPS',
    'Saving or editing records': 'Enregistrement ou modification des données',
    'Offline use or syncing': 'Utilisation hors ligne ou synchronisation',
    'Navigation': 'Navigation',
    'Coordinates or datums': 'Coordonnées ou datums',
    'Finding features': 'Recherche de fonctionnalités',
    'Nothing is difficult': 'Rien n’est difficile',
    'Response saved. It will sync automatically.':
        'Réponse enregistrée. Elle sera synchronisée automatiquement.',
    'Could not load more cloud records.':
        'Impossible de charger davantage d’enregistrements cloud.',
    'No matching saved locations': 'Aucun lieu enregistré correspondant',
    'Try changing search text, filter, sort, or group.':
        'Essayez de modifier le texte de recherche, le filtre, le tri ou le groupe.',
    'Dismiss': 'Ignorer',
    'More': 'Plus',
    'Sort': 'Trier',
    'Filter': 'Filtrer',
    'Undo': 'Annuler',
    'Clear': 'Effacer',
    'Distance': 'Distance',
    'Area': 'Surface',
    'Marker': 'Repère',
    'Points': 'Points',
    'Total': 'Total',
    'Perimeter': 'Périmètre',
    'Place': 'Lieu',
    'Description': 'Description',
    'Current password': 'Mot de passe actuel',
    'New password': 'Nouveau mot de passe',
    'Confirm password': 'Confirmer le mot de passe',
    'Email address': 'Adresse e-mail',
    'Phone number': 'Numéro de téléphone',
    'Password': 'Mot de passe',
    'Sign in to your account': 'Connectez-vous à votre compte',
    'Tap to copy': 'Appuyez pour copier',
    'Tap to email': 'Appuyez pour envoyer un e-mail',
    'Tap to call': 'Appuyez pour appeler',
    'We’d love to hear from you': 'Nous aimerions avoir de vos nouvelles',
    'Reach out anytime for support, feedback, or suggestions.':
        'Contactez-nous à tout moment pour obtenir de l’aide, donner votre avis ou faire des suggestions.',
    'Verification code': 'Code de vérification',
    'Send verification code': 'Envoyer le code de vérification',
    'Update password': 'Modifier le mot de passe',
    'Media deleted.': 'Média supprimé.',
    'Location media': 'Médias de la position',
    'Sign in to view uploaded media':
        'Connectez-vous pour voir les médias téléversés',
    'Your cloud media will appear here once you sign in with a verified account.':
        'Vos médias dans le cloud apparaîtront ici une fois connecté avec un compte vérifié.',
    'No uploaded media found yet.': 'Aucun média téléversé pour le moment.',
    'Media': 'Média',
    'Unnamed location': 'Position sans nom',
    'File name': 'Nom du fichier',
    'Path': 'Chemin',
    'MIME': 'MIME',
    'Size': 'Taille',
    'Location ID': 'Identifiant de la position',
    'Play': 'Lire',
    'Pause': 'Pause',
    'Sign in to delete media.': 'Connectez-vous pour supprimer ce média.',
    'Delete media?': 'Supprimer le média ?',
    'This will permanently delete the media from the server.':
        'Ce média sera définitivement supprimé du serveur.',
    'Failed to download media for sharing.':
        'Échec du téléchargement du média à partager.',
    'Failed to share media.': 'Échec du partage du média.',
    'Failed to capture GPS photo. Try again.':
        'Échec de la capture de la photo GPS. Réessayez.',
    'Video saved to gallery': 'Vidéo enregistrée dans la galerie',
    'Photo saved to gallery': 'Photo enregistrée dans la galerie',
    'Could not save to gallery — file not found.':
        'Impossible d’enregistrer dans la galerie : fichier introuvable.',
    'Could not save media to gallery. Check permissions.':
        'Impossible d’enregistrer le média dans la galerie. Vérifiez les autorisations.',
    'This will delete the media from this device and from the cloud if uploaded.':
        'Le média sera supprimé de cet appareil et du cloud s’il a été téléversé.',
    'Failed to capture photo.': 'Échec de la capture de la photo.',
    'Failed to stop video recording.':
        'Échec de l’arrêt de l’enregistrement vidéo.',
    'Retake': 'Reprendre',
    'Account refreshed': 'Compte actualisé',
    'Logged out successfully': 'Déconnexion réussie',
    'Could not open Ardhi web app':
        'Impossible d’ouvrir l’application web Ardhi',
    'Full name': 'Nom complet',
    'Name is required': 'Le nom est obligatoire',
    'Email is required': 'L’adresse e-mail est obligatoire',
    'Current password is required': 'Le mot de passe actuel est obligatoire',
    'New password is required': 'Le nouveau mot de passe est obligatoire',
    'Minimum 8 characters': '8 caractères minimum',
    'Confirm new password': 'Confirmer le nouveau mot de passe',
    'Confirm your new password': 'Confirmez votre nouveau mot de passe',
    'Passwords do not match': 'Les mots de passe ne correspondent pas',
    '1 Request code': '1 Demander le code',
    '2 Confirm deletion': '2 Confirmer la suppression',
    'No email found': 'Aucune adresse e-mail trouvée',
    'This action is irreversible. All tokens will be revoked and your account data will be deleted after code confirmation.':
        'Cette action est irréversible. Tous les jetons seront révoqués et les données de votre compte seront supprimées après confirmation du code.',
    'Enter the 6-digit code sent to your email.':
        'Saisissez le code à 6 chiffres envoyé à votre adresse e-mail.',
    'Enter the 6-digit verification code':
        'Saisissez le code de vérification à 6 chiffres',
    'Delete my account': 'Supprimer mon compte',
    'Back to password step': 'Retour à l’étape du mot de passe',
    'you@example.com': 'vous@exemple.com',
    'Enter your password': 'Saisissez votre mot de passe',
    'John': 'Jean',
    'Doe': 'Dupont',
    'Min. 8 characters': '8 caractères minimum',
    'Repeat your password': 'Répétez votre mot de passe',
    'View more': 'Voir plus',
    'Could not open the app store.':
        'Impossible d’ouvrir la boutique d’applications.',
    'Could not open privacy policy':
        'Impossible d’ouvrir la politique de confidentialité',
    'Email app opened — tap Send to submit.':
        'Application e-mail ouverte — appuyez sur Envoyer pour transmettre.',
    'Something went wrong. Please try again.':
        'Une erreur est survenue. Veuillez réessayer.',
    'File': 'Fichier',
    'Location is turned off': 'La localisation est désactivée',
    'Location access is blocked': 'L’accès à la localisation est bloqué',
    'Location access is off': 'L’accès à la localisation est désactivé',
    'TaREF GPS needs Location Services for live coordinates, GPS point capture, navigation, distance tracking, and media geotagging. You can use the app without live GPS features.':
        'TaREF GPS a besoin des services de localisation pour les coordonnées en direct, la capture de points GPS, la navigation, le suivi des distances et la géolocalisation des médias. Vous pouvez utiliser l’application sans les fonctions GPS en direct.',
    'Location access is blocked for TaREF GPS. Enable it in Settings to use live coordinates, GPS point capture, navigation, distance tracking, and media geotagging. You can use the app without live GPS features.':
        'L’accès à la localisation est bloqué pour TaREF GPS. Activez-le dans les réglages pour utiliser les coordonnées en direct, la capture de points GPS, la navigation, le suivi des distances et la géolocalisation des médias. Vous pouvez utiliser l’application sans les fonctions GPS en direct.',
    'TaREF GPS uses location for live coordinates, GPS point capture, navigation, distance tracking, and media geotagging. You can use the app without live GPS features.':
        'TaREF GPS utilise la localisation pour les coordonnées en direct, la capture de points GPS, la navigation, le suivi des distances et la géolocalisation des médias. Vous pouvez utiliser l’application sans les fonctions GPS en direct.',
    'Turn On Location': 'Activer la localisation',
    'Maybe Later': 'Plus tard',
    'My current location': 'Ma position actuelle',
    'My location {date}': 'Ma position {date}',
    'Lat/Long': 'Lat/Long',
    'Lat / Lng': 'Lat / Long',
    'E/N': 'Est/Nord',
    'E': 'E',
    'N': 'N',
    '{count} selected': '{count} sélectionnés',
    'General': 'Général',
    'All groups': 'Tous les groupes',
    'Cloud': 'Cloud',
    'Cloud land': 'Terrain cloud',
    'Cloud records only': 'Enregistrements cloud uniquement',
    'Cloud only': 'Cloud uniquement',
    '3+ points': '3 points ou plus',
    'Source': 'Source',
    'Saved location': 'Lieu enregistré',
    'Saved': 'Enregistrés',
    'Library': 'Bibliothèque',
    'Add manually': 'Ajouter manuellement',
    'Updating cloud records...': 'Mise à jour des enregistrements cloud…',
    'Loading more records...': 'Chargement d’autres enregistrements…',
    'Failed to load coordinates. Check your connection and try again.':
        'Impossible de charger les coordonnées. Vérifiez votre connexion et réessayez.',
    'Cloud deletion requires a valid session and land id.':
        'La suppression cloud nécessite une session valide et un identifiant de terrain.',
    'Unknown': 'Inconnu',
    'Saved to cloud': 'Enregistré dans le cloud',
    'Saved {date}': 'Enregistré le {date}',
    'Updated {date}': 'Mis à jour le {date}',
    'Actions for {name}': 'Actions pour {name}',
    'Show less': 'Afficher moins',
    'Show all {count} points': 'Afficher les {count} points',
    'Points ({count})': 'Points ({count})',
    'Point {count}': 'Point {count}',
    '{count} point': '{count} point',
    '{count} points': '{count} points',
    '{count} result': '{count} résultat',
    '{count} results': '{count} résultats',
    'Showing latest {count} records. Use the web app to view older records.':
        'Affichage des {count} enregistrements les plus récents. Utilisez l’application web pour voir les anciens enregistrements.',
    'Newest': 'Plus récents',
    'Oldest': 'Plus anciens',
    'This will delete "{name}" from the server.':
        '« {name} » sera supprimé du serveur.',
    'This will delete {count} selected items. This action cannot be undone.':
        'Les {count} éléments sélectionnés seront supprimés. Cette action est irréversible.',
    'Deleted {count} selected item': '{count} élément sélectionné supprimé',
    'Deleted {count} selected items': '{count} éléments sélectionnés supprimés',
    'Enter valid latitude and longitude.':
        'Saisissez une latitude et une longitude valides.',
    'Latitude must be between -90 and 90.':
        'La latitude doit être comprise entre -90 et 90.',
    'Longitude must be between -180 and 180.':
        'La longitude doit être comprise entre -180 et 180.',
    'Coordinates 0, 0 point to the Gulf of Guinea. Please enter real coordinates.':
        'Les coordonnées 0, 0 se trouvent dans le golfe de Guinée. Saisissez des coordonnées réelles.',
    'These coordinates are near 0,0 which is unlikely to be a real location.':
        'Ces coordonnées sont proches de 0,0, ce qui est peu probable pour un lieu réel.',
    'Point {count} added.': 'Point {count} ajouté.',
    'Enter valid easting and northing.':
        'Saisissez des valeurs Est et Nord valides.',
    'Zone number is required.': 'Le numéro de zone est obligatoire.',
    'Zone must be between 1 and 60.':
        'La zone doit être comprise entre 1 et 60.',
    'Easting must be between 100,000 and 900,000 meters.':
        'La coordonnée Est doit être comprise entre 100 000 et 900 000 mètres.',
    'Northing must be between 0 and 10,000,000 meters.':
        'La coordonnée Nord doit être comprise entre 0 et 10 000 000 mètres.',
    'Band letter must be C-X (excluding I and O).':
        'La lettre de bande doit être comprise entre C et X (sauf I et O).',
    'Could not convert these UTM values to coordinates. Check your input.':
        'Impossible de convertir ces valeurs UTM en coordonnées. Vérifiez votre saisie.',
    'UTM values produce invalid coordinates. Please verify easting, northing, and zone.':
        'Les valeurs UTM produisent des coordonnées invalides. Vérifiez les valeurs Est, Nord et la zone.',
    'Name is required.': 'Le nom est obligatoire.',
    'Add at least one point.': 'Ajoutez au moins un point.',
    'Saved and synced to cloud!': 'Enregistré et synchronisé avec le cloud !',
    'Saved locally. Cloud sync failed: {error}':
        'Enregistré localement. Échec de la synchronisation cloud : {error}',
    'Saved locally. Will sync when logged in.':
        'Enregistré localement. La synchronisation aura lieu après la connexion.',
    'Failed to save: {error}': 'Échec de l’enregistrement : {error}',
    'No saved locations': 'Aucun lieu enregistré',
    'Your saved places will appear here.':
        'Vos lieux enregistrés apparaîtront ici.',
  };

  static const _ar = <String, String>{
    'TaREF GPS-Coordinates': 'TaREF GPS-Coordinates',
    'Sign in to your account': 'سجّل الدخول إلى حسابك',
    'Join Taref Gps today': 'انضم إلى Taref GPS اليوم',
    'Email address': 'عنوان البريد الإلكتروني',
    'Password': 'كلمة المرور',
    'you@example.com': 'you@example.com',
    'John': 'محمد',
    'Doe': 'أحمد',
    'Could not open terms and conditions': 'تعذر فتح الشروط والأحكام',
    'Enter the reset token from email and choose a new password.':
        'أدخل رمز إعادة التعيين المرسل بالبريد الإلكتروني واختر كلمة مرور جديدة.',
    'Reset token': 'رمز إعادة التعيين',
    'Confirm password': 'تأكيد كلمة المرور',
    'Account refreshed': 'تم تحديث الحساب',
    'Stop cloud sync on this device and keep local data':
        'إيقاف المزامنة السحابية على هذا الجهاز مع الاحتفاظ بالبيانات المحلية',
    'Logged out successfully': 'تم تسجيل الخروج بنجاح',
    'Permanently delete your account. You will need your password and email access to confirm.':
        'احذف حسابك نهائيًا. ستحتاج إلى كلمة المرور والوصول إلى بريدك الإلكتروني للتأكيد.',
    'This action is irreversible. All tokens will be revoked and your account data will be deleted after code confirmation.':
        'هذا الإجراء لا يمكن التراجع عنه. ستُلغى جميع رموز الدخول وستُحذف بيانات حسابك بعد تأكيد الرمز.',
    'Enter the 6-digit code sent to your email.':
        'أدخل الرمز المكوّن من 6 أرقام المرسل إلى بريدك الإلكتروني.',
    'Enter the 6-digit verification code': 'أدخل رمز التحقق المكوّن من 6 أرقام',
    'Required': 'مطلوب',
    'Enter a valid email': 'أدخل بريدًا إلكترونيًا صالحًا',
    'Password is required': 'كلمة المرور مطلوبة',
    'Password must be at least 6 characters':
        'يجب أن تتكون كلمة المرور من 6 أحرف على الأقل',
    "Don't have an account? ": 'ليس لديك حساب؟ ',
    'Send Reset Link': 'إرسال رابط إعادة التعيين',
    'Remembered your password? ': 'تذكرت كلمة المرور؟ ',
    'Token is required': 'رمز إعادة التعيين مطلوب',
    'Confirm your password': 'أكد كلمة المرور',
    'Must include uppercase & number': 'يجب أن تحتوي على حرف كبير ورقم',
    'Please confirm your password': 'يرجى تأكيد كلمة المرور',
    'I agree to the ': 'أوافق على ',
    'Terms and Conditions': 'الشروط والأحكام',
    'You must accept the terms to continue.':
        'يجب الموافقة على الشروط للمتابعة.',
    'Send a new verification email to {email}':
        'إرسال رسالة تحقق جديدة إلى {email}',
    'Email not verified': 'البريد الإلكتروني غير موثّق',
    'A verification code will be sent to your email address. The request is throttled to 3 times per minute.':
        'سيُرسل رمز تحقق إلى بريدك الإلكتروني. يمكنك طلبه 3 مرات في الدقيقة.',
    'The confirm request is throttled to 6 times per minute.':
        'يمكنك تأكيد الطلب 6 مرات في الدقيقة.',
    'Login failed. Please try again.': 'فشل تسجيل الدخول. حاول مرة أخرى.',
    'Registration failed. Please try again.':
        'فشل إنشاء الحساب. حاول مرة أخرى.',
    'Failed to request password reset.': 'تعذر طلب إعادة تعيين كلمة المرور.',
    'Failed to reset password.': 'تعذر إعادة تعيين كلمة المرور.',
    'Failed to update profile.': 'تعذر تحديث الملف الشخصي.',
    'Failed to update password.': 'تعذر تحديث كلمة المرور.',
    'Failed to send verification email.': 'تعذر إرسال رسالة التحقق.',
    'Failed to request account deletion.': 'تعذر طلب حذف الحساب.',
    'Failed to confirm account deletion.': 'تعذر تأكيد حذف الحساب.',
    'Unable to connect. Check your internet connection.':
        'تعذر الاتصال. تحقق من اتصالك بالإنترنت.',
    'Land Mapper': 'خرائط الأراضي',
    'Settings': 'الإعدادات',
    'Account': 'الحساب',
    'Sign In': 'تسجيل الدخول',
    'Sign in': 'تسجيل الدخول',
    'Sign out': 'تسجيل الخروج',
    'Logout': 'تسجيل الخروج',
    'Create account': 'إنشاء حساب',
    'Connect this device to your cloud account':
        'ربط هذا الجهاز بحسابك السحابي',
    'Register a new account for sync access':
        'إنشاء حساب جديد للوصول إلى المزامنة',
    'Request password reset by email':
        'طلب إعادة تعيين كلمة المرور عبر البريد الإلكتروني',
    'Profile': 'الملف الشخصي',
    'Edit name, email and phone number':
        'تعديل الاسم والبريد الإلكتروني ورقم الهاتف',
    'Update your account password': 'تحديث كلمة مرور حسابك',
    'Open TaREF web app': 'فتح تطبيق TaREF على الويب',
    'Manage your data at ardhi.co.tz': 'إدارة بياناتك على ardhi.co.tz',
    'Verification': 'التحقق',
    'Resend verification email': 'إعادة إرسال رسالة التحقق',
    'Session': 'الجلسة',
    'Danger zone': 'منطقة الخطر',
    'Register': 'تسجيل',
    'Forgot password': 'نسيت كلمة المرور',
    'Forgot password?': 'هل نسيت كلمة المرور؟',
    'Change password': 'تغيير كلمة المرور',
    'Change Password': 'تغيير كلمة المرور',
    'Reset Password': 'إعادة تعيين كلمة المرور',
    'Enter your email to receive a reset link':
        'أدخل بريدك الإلكتروني لاستلام رابط إعادة التعيين',
    'Account Created!': 'تم إنشاء الحساب!',
    'Sign In Now': 'تسجيل الدخول الآن',
    'Create Account': 'إنشاء حساب',
    'First Name': 'الاسم الأول',
    'Last Name': 'اسم العائلة',
    'Confirm Password': 'تأكيد كلمة المرور',
    'Already have an account? ': 'لديك حساب بالفعل؟ ',
    'Reset password': 'إعادة تعيين كلمة المرور',
    'Update Profile': 'تحديث الملف الشخصي',
    'Update profile': 'تحديث الملف الشخصي',
    'Profile updated successfully': 'تم تحديث الملف الشخصي بنجاح',
    'Save changes': 'حفظ التغييرات',
    'Cancel': 'إلغاء',
    'Save': 'حفظ',
    'Delete': 'حذف',
    'Delete account': 'حذف الحساب',
    'Delete account?': 'حذف الحساب؟',
    'Delete marker': 'حذف العلامة',
    'Back': 'رجوع',
    'Close': 'إغلاق',
    'Done': 'تم',
    'Enable': 'تفعيل',
    'Grant Permission': 'منح الإذن',
    'Cloud synchronization': 'المزامنة السحابية',
    'Signed in': 'تم تسجيل الدخول',
    'Sign in only when you want to sync data to the server.':
        'سجّل الدخول فقط عندما تريد مزامنة البيانات مع الخادم.',
    'Location Settings': 'إعدادات الموقع',
    'Coordinates format': 'تنسيق الإحداثيات',
    'Decimal Degrees': 'درجات عشرية',
    'Degrees Minutes Seconds': 'درجات ودقائق وثوانٍ',
    'Degrees Decimal Minutes': 'درجات ودقائق عشرية',
    'Example: {coordinates}': 'مثال: {coordinates}',
    'Minna — Nigeria': 'مينا — نيجيريا',
    'Arc 1960 — Kenya/Tanzania mean': 'آرك 1960 — متوسط كينيا/تنزانيا',
    'Arc 1960 — Kenya': 'آرك 1960 — كينيا',
    'Arc 1960 — Tanzania': 'آرك 1960 — تنزانيا',
    'Arc 1950 — Southern Africa mean': 'آرك 1950 — متوسط الجنوب الأفريقي',
    'NAD27 — CONUS': 'NAD27 — الولايات المتحدة المتجاورة',
    'NAD83 — North America': 'NAD83 — أمريكا الشمالية',
    'ETRS89 — Europe': 'ETRS89 — أوروبا',
    'GDA94 — Australia': 'GDA94 — أستراليا',
    'SAD69 — South America mean': 'SAD69 — متوسط أمريكا الجنوبية',
    'WGS 72 — global': 'WGS 72 — عالمي',
    'Nigeria — onshore and offshore': 'نيجيريا — برًا وبحرًا',
    'Kenya and Tanzania': 'كينيا وتنزانيا',
    'Kenya — onshore': 'كينيا — برًا',
    'Tanzania — onshore': 'تنزانيا — برًا',
    'Botswana, Eswatini, Lesotho, Malawi, Zambia and Zimbabwe':
        'بوتسوانا وإسواتيني وليسوتو وملاوي وزامبيا وزيمبابوي',
    'Contiguous United States — onshore': 'الولايات المتحدة المتجاورة — برًا',
    'North America': 'أمريكا الشمالية',
    'Europe — onshore and offshore': 'أوروبا — برًا وبحرًا',
    'Australia and external territories': 'أستراليا والأقاليم الخارجية',
    'South America onshore north of 45°S, excluding Amazonia':
        'أمريكا الجنوبية برًا شمال 45° جنوبًا، باستثناء الأمازون',
    'World': 'العالم',
    'Geodetic datum': 'المرجع الجيوديسي',
    'Select datum': 'اختر المرجع الجيوديسي',
    'Choose the datum used by your survey. Its reference ellipsoid is shown below the datum name.':
        'اختر المرجع الجيوديسي المستخدم في المسح. يظهر الشكل الإهليلجي المرجعي أسفل اسم المرجع.',
    'WGS 84 ellipsoid • Global reference system (default; valid everywhere)':
        'الشكل الإهليلجي WGS 84 • نظام مرجعي عالمي (افتراضي؛ صالح في كل مكان)',
    '{ellipsoid} ellipsoid • {area}\nEPSG:{code} • {accuracy} m accuracy':
        'الشكل الإهليلجي {ellipsoid} • {area}\nEPSG:{code} • دقة {accuracy} م',
    ' • Approximate': ' • تقريبي',
    ' • Valid here': ' • صالح هنا',
    'REFERENCE / ELLIPSOID-ONLY OPTIONS': 'خيارات المرجع / الشكل الإهليلجي فقط',
    '{ellipsoid} ellipsoid • No verified datum transformation; ellipsoid-shape-only conversion':
        'الشكل الإهليلجي {ellipsoid} • لا يوجد تحويل مرجعي متحقق منه؛ تحويل شكل الإهليلج فقط',
    'Coordinates now shown in {datum}': 'تُعرض الإحداثيات الآن وفق {datum}',
    'Error changing coordinate display: {error}':
        'خطأ أثناء تغيير عرض الإحداثيات: {error}',
    'Compass north reference': 'مرجع الشمال في البوصلة',
    'True North (geographic)': 'الشمال الحقيقي (الجغرافي)',
    'Units': 'الوحدات',
    'Meters': 'أمتار',
    'Feet': 'أقدام',
    'Use meters (m)': 'استخدام الأمتار (م)',
    'Use feet (ft)': 'استخدام الأقدام (قدم)',
    'Magnetic North': 'الشمال المغناطيسي',
    'True North': 'الشمال الحقيقي',
    'Uses raw compass sensor reading. No correction applied.':
        'يستخدم القراءة المباشرة لمستشعر البوصلة. لا يُطبّق أي تصحيح.',
    'Corrects for magnetic declination to point to geographic north.':
        'يصحح الانحراف المغناطيسي للإشارة إلى الشمال الجغرافي.',
    'Photo': 'صورة',
    'Save original photo': 'حفظ الصورة الأصلية',
    'Save with no data on it. Useful for editing before sharing.':
        'احفظ الصورة دون بيانات مضافة. مفيد لتحريرها قبل مشاركتها.',
    'Save to gallery': 'حفظ في المعرض',
    'Save image with data': 'حفظ الصورة مع البيانات',
    'Privacy policy': 'سياسة الخصوصية',
    'Cache': 'ذاكرة التخزين المؤقت',
    'Clear cache': 'مسح ذاكرة التخزين المؤقت',
    'Clear cache?': 'مسح ذاكرة التخزين المؤقت؟',
    'Remove cached data and temporary files':
        'إزالة البيانات المخزنة مؤقتًا والملفات المؤقتة',
    'Cache cleared successfully': 'تم مسح ذاكرة التخزين المؤقت بنجاح',
    'Cache cleared successfully (~{size} MB freed)':
        'تم مسح ذاكرة التخزين المؤقت بنجاح (تحرير نحو {size} ميغابايت)',
    'Error clearing cache: {error}':
        'خطأ أثناء مسح ذاكرة التخزين المؤقت: {error}',
    'This will clear all cached data including images, temporary files, and app cache storage. Your saved locations will not be affected.':
        'سيؤدي هذا إلى مسح جميع البيانات المخزنة مؤقتًا، بما فيها الصور والملفات المؤقتة وذاكرة التطبيق. لن تتأثر المواقع المحفوظة.',
    'Preview ready. Open Library. Submitting the form sends a real response.':
        'المعاينة جاهزة. افتح المكتبة. سيؤدي إرسال النموذج إلى إرسال رد فعلي.',
    'Information': 'معلومات',
    'Contact us': 'اتصل بنا',
    'Send suggestions or report a bug. We appreciate your feedback.':
        'أرسل اقتراحاتك أو أبلغ عن خلل. نقدر ملاحظاتك.',
    'Send feedback': 'إرسال ملاحظات',
    '[TaREF GPS] Feedback': '[TaREF GPS] ملاحظات',
    'We read every message': 'نقرأ كل رسالة',
    'Tell us what\'s on your mind — a bug, suggestion, or question…':
        'أخبرنا بما يدور في ذهنك — خلل أو اقتراح أو سؤال…',
    'Send': 'إرسال',
    'No email app found. Message copied — send it to {email}':
        'لم يُعثر على تطبيق بريد إلكتروني. نُسخت الرسالة — أرسلها إلى {email}',
    'Device': 'الجهاز',
    'Product': 'المنتج',
    'Model': 'الطراز',
    'App version': 'إصدار التطبيق',
    'Platform': 'النظام',
    'Share your experience': 'شارك تجربتك',
    'Tell us what works and what is difficult.':
        'أخبرنا بما يعمل جيدًا وما الذي تجده صعبًا.',
    'Preview survey invitation': 'معاينة دعوة الاستبيان',
    'Debug only. Open Library after tapping.':
        'للتصحيح فقط. افتح المكتبة بعد الضغط.',
    'Rate our app': 'قيّم تطبيقنا',
    'Leave a rating or review in the app store.':
        'اترك تقييمًا أو مراجعة في متجر التطبيقات.',
    'Version': 'الإصدار',
    'Loading version...': 'جارٍ تحميل الإصدار...',
    'Version unavailable': 'الإصدار غير متاح',
    'Reading build metadata from the app package...':
        'جارٍ قراءة بيانات الإصدار من حزمة التطبيق…',
    'This comes from the installed app metadata.':
        'تأتي هذه المعلومات من بيانات التطبيق المثبت.',
    'Other': 'أخرى',
    'Language': 'اللغة',
    'System default': 'إعدادات النظام الافتراضية',
    'English': 'الإنجليزية',
    'French': 'الفرنسية',
    'Arabic': 'العربية',
    'Map': 'الخريطة',
    'Map Type': 'نوع الخريطة',
    'Normal': 'عادية',
    'Satellite': 'قمر صناعي',
    'Terrain': 'تضاريس',
    'Hybrid': 'مختلطة',
    'Layers': 'الطبقات',
    'Field': 'الحقل',
    'My location': 'موقعي',
    'My Location': 'موقعي',
    'Compass accuracy': 'دقة البوصلة',
    'UTM Zone': 'منطقة UTM',
    'Easting': 'الإحداثي الشرقي',
    'Northing': 'الإحداثي الشمالي',
    'Altitude': 'الارتفاع',
    'Accuracy': 'الدقة',
    'Signal': 'الإشارة',
    'Location age': 'عمر الموقع',
    'Tracking': 'التتبع',
    'Speed': 'السرعة',
    'Lat/Lon': 'خط العرض/خط الطول',
    'Motion': 'الحركة',
    'Heading': 'الاتجاه',
    'Reference': 'المرجع',
    'Display datum': 'المرجع المعروض',
    'Captured at': 'تم الالتقاط في',
    'Location note': 'ملاحظة الموقع',
    'Zone': 'المنطقة',
    'Format': 'التنسيق',
    'Datum': 'المرجع',
    'Updated': 'تم التحديث',
    'Saved locations': 'المواقع المحفوظة',
    'Location': 'الموقع',
    'Coordinates': 'الإحداثيات',
    'Address': 'العنوان',
    'Phone': 'الهاتف',
    'Email': 'البريد الإلكتروني',
    'System': 'النظام',
    'All': 'الكل',
    'Images': 'الصور',
    'Videos': 'الفيديوهات',
    'Copy coordinates': 'نسخ الإحداثيات',
    'Share location': 'مشاركة الموقع',
    'Save location': 'حفظ الموقع',
    'Dismiss': 'تجاهل',
    'EASTING': 'الإحداثي الشرقي',
    'NORTHING': 'الإحداثي الشمالي',
    'Live location is unavailable': 'الموقع المباشر غير متاح',
    'Live coordinates and GPS tracking are off. Other app features remain available.':
        'الإحداثيات المباشرة وتتبع GPS متوقفان. تظل الميزات الأخرى متاحة.',
    'Enable live location?': 'هل تريد تفعيل الموقع المباشر؟',
    'TaREF GPS needs Location Services to display live coordinates, track your position, save GPS points, support navigation, and geotag captured photos or videos. You can continue using other app features without live location.':
        'يحتاج TaREF GPS إلى خدمات الموقع لعرض الإحداثيات المباشرة وتتبع موقعك وحفظ نقاط GPS ودعم الملاحة وتحديد مواقع الصور أو الفيديوهات. يمكنك متابعة استخدام الميزات الأخرى دون الموقع المباشر.',
    'Location access is blocked for TaREF GPS. Enable it in Settings to display live coordinates, save your current position, support navigation, and geotag media. You can continue using the app without live GPS.':
        'الوصول إلى الموقع محظور لتطبيق TaREF GPS. فعّله في الإعدادات لعرض الإحداثيات المباشرة وحفظ موقعك ودعم الملاحة وتحديد مواقع الوسائط. يمكنك متابعة استخدام التطبيق دون GPS مباشر.',
    'TaREF GPS uses your current location only for GPS features such as live coordinates, position tracking, saved points, navigation, and automatic photo or video geotagging. Other app features remain available without it.':
        'يستخدم TaREF GPS موقعك الحالي فقط لميزات GPS، مثل الإحداثيات المباشرة والتتبع والنقاط المحفوظة والملاحة وتحديد مواقع الصور أو الفيديوهات تلقائيًا. تظل الميزات الأخرى متاحة دون ذلك.',
    'System camera mode is not available yet, using in-app camera.':
        'وضع كاميرا النظام غير متاح بعد؛ سيتم استخدام كاميرا التطبيق.',
    'Location tracking is active': 'تتبع الموقع نشط',
    'TaREF GPS - Coordinates': 'TaREF GPS - الإحداثيات',
    'Coordinates unavailable': 'الإحداثيات غير متاحة',
    'Video deleted': 'تم حذف الفيديو',
    'Photo deleted': 'تم حذف الصورة',
    'GPS Camera': 'كاميرا GPS',
    'GPS Capture': 'لقطة GPS',
    'Preview': 'معاينة',
    'Camera permission is denied. Allow camera permission in app settings.':
        'تم رفض إذن الكاميرا. اسمح بالوصول إليها من إعدادات التطبيق.',
    'Failed to open camera. Please try again.':
        'تعذر فتح الكاميرا. يرجى المحاولة مرة أخرى.',
    'Failed to capture GPS photo. Try again.':
        'تعذر التقاط صورة GPS. حاول مرة أخرى.',
    'Delete media?': 'حذف الوسائط؟',
    'Media deleted.': 'تم حذف الوسائط.',
    'Location media': 'وسائط الموقع',
    'Sign in to view uploaded media': 'سجّل الدخول لعرض الوسائط المرفوعة',
    'Your cloud media will appear here once you sign in with a verified account.':
        'ستظهر وسائطك السحابية هنا بعد تسجيل الدخول بحساب تم التحقق منه.',
    'No uploaded media found yet.': 'لم يُعثر على وسائط مرفوعة بعد.',
    'Media': 'وسائط',
    'Unnamed location': 'موقع بلا اسم',
    'File name': 'اسم الملف',
    'Path': 'المسار',
    'MIME': 'MIME',
    'Size': 'الحجم',
    'Location ID': 'معرّف الموقع',
    'Play': 'تشغيل',
    'Pause': 'إيقاف مؤقت',
    'Sign in to delete media.': 'سجّل الدخول لحذف الوسائط.',
    'This will permanently delete the media from the server.':
        'سيؤدي هذا إلى حذف الوسائط نهائيًا من الخادم.',
    'Failed to download media for sharing.': 'فشل تنزيل الوسائط للمشاركة.',
    'Failed to share media.': 'فشلت مشاركة الوسائط.',
    'Video saved to gallery': 'تم حفظ الفيديو في المعرض',
    'Photo saved to gallery': 'تم حفظ الصورة في المعرض',
    'Retake': 'إعادة الالتقاط',
    '{media} saved locally. Cloud upload failed.':
        'تم حفظ {media} محليًا. فشل الرفع إلى السحابة.',
    'Video': 'فيديو',
    'Good': 'جيدة',
    'Fair': 'متوسطة',
    'Poor': 'ضعيفة',
    'Compass': 'البوصلة',
    'Unavailable': 'غير متاح',
    'North': 'الشمال',
    'North East': 'الشمال الشرقي',
    'East': 'الشرق',
    'South East': 'الجنوب الشرقي',
    'South': 'الجنوب',
    'South West': 'الجنوب الغربي',
    'West': 'الغرب',
    'North West': 'الشمال الغربي',
    'Magnetic': 'مغناطيسي',
    'Not reported': 'غير مبلّغ عنها',
    'High': 'عالية',
    'Moderate': 'متوسطة',
    'Low': 'منخفضة',
    'Compass sensor unavailable on this device.':
        'مستشعر البوصلة غير متاح على هذا الجهاز.',
    'Live compass · {north}': 'بوصلة مباشرة · {north}',
    'Location permission is required for the compass sensor on Android.':
        'يلزم إذن الموقع لاستخدام مستشعر البوصلة على أندرويد.',
    'Initializing GPS…': 'جارٍ تهيئة GPS…',
    'Live tracking': 'تتبع مباشر',
    'Tracking paused': 'التتبع متوقف مؤقتًا',
    'GPS media details': 'تفاصيل وسائط GPS',
    'UTM unavailable for this latitude':
        'إحداثيات UTM غير متاحة عند خط العرض هذا',
    'Camera permission is blocked': 'إذن الكاميرا محظور',
    'Camera permission is required': 'إذن الكاميرا مطلوب',
    'Failed to initialize the camera': 'تعذر تهيئة الكاميرا',
    'Open app settings and allow camera access to take GPS photos.':
        'افتح إعدادات التطبيق واسمح بالوصول إلى الكاميرا لالتقاط صور GPS.',
    'Grant camera permission to capture GPS-tagged photos and videos.':
        'امنح إذن الكاميرا لالتقاط صور وفيديوهات محددة الموقع.',
    'Something went wrong. Try again or check your device camera.':
        'حدث خطأ ما. حاول مرة أخرى أو تحقق من كاميرا جهازك.',
    'Try Again': 'حاول مرة أخرى',
    'Location service is disabled.': 'خدمة الموقع معطلة.',
    'Location is off. Media will be saved without a GPS tag.':
        'الموقع متوقف. سيتم حفظ الوسائط دون بيانات GPS.',
    'Unable to resolve current location.': 'تعذر تحديد الموقع الحالي.',
    'Live location updates failed.': 'فشل تحديث الموقع المباشر.',
    'Recording… Tap to stop': 'جارٍ التسجيل… اضغط للإيقاف',
    'Tap to record video': 'اضغط لتسجيل فيديو',
    'Tap to capture photo': 'اضغط لالتقاط صورة',
    'Recent media': 'الوسائط الحديثة',
    'No local media yet': 'لا توجد وسائط محلية بعد',
    'No photos captured yet': 'لم تُلتقط صور بعد',
    'Tap to view cloud media': 'اضغط لعرض الوسائط السحابية',
    'Tap to capture your first photo': 'اضغط لالتقاط صورتك الأولى',
    'Date {date}': 'التاريخ: {date}',
    'Street {street}': 'الشارع: {street}',
    'Place {place}': 'المكان: {place}',
    'Coordinates {coordinates}': 'الإحداثيات: {coordinates}',
    'Accuracy {accuracy}': 'الدقة: {accuracy}',
    'Waiting for GPS details': 'بانتظار تفاصيل GPS',
    'Address unavailable': 'العنوان غير متاح',
    'Could not save to gallery — file not found.':
        'تعذر الحفظ في المعرض — الملف غير موجود.',
    'Could not save media to gallery. Check permissions.':
        'تعذر حفظ الوسائط في المعرض. تحقق من الأذونات.',
    'This will delete the media from this device and from the cloud if uploaded.':
        'سيتم حذف الوسائط من هذا الجهاز ومن السحابة إذا رُفعت إليها.',
    'Failed to capture photo.': 'فشل التقاط الصورة.',
    'Failed to stop video recording.': 'فشل إيقاف تسجيل الفيديو.',
    'Place name': 'اسم المكان',
    'Enter place name': 'أدخل اسم المكان',
    'Skip': 'تخطي',
    'Search saved locations': 'البحث في المواقع المحفوظة',
    'Search': 'بحث',
    'Select multiple': 'تحديد عدة عناصر',
    'Newest first': 'الأحدث أولاً',
    'Oldest first': 'الأقدم أولاً',
    'Name A-Z': 'الاسم أ-ي',
    'Name Z-A': 'الاسم ي-أ',
    'Most points': 'أكثر نقاط',
    'Location saved': 'تم حفظ الموقع',
    'Center here': 'توسيط هنا',
    'Update Area': 'تحديث المساحة',
    'Create Area': 'إنشاء مساحة',
    'Capture boundary points and save your land details.':
        'التقط نقاط الحدود واحفظ تفاصيل أرضك.',
    'Place *': 'المكان *',
    'Phone (optional)': 'الهاتف (اختياري)',
    'Description (optional)': 'الوصف (اختياري)',
    'e.g. 0712345678': 'مثلاً 0712345678',
    'Add notes about this land': 'أضف ملاحظات حول هذه الأرض',
    'Boundary capture': 'التقاط الحدود',
    'Mark current Location while walking around the field boundary.':
        'حدّد موقعك الحالي أثناء السير حول حدود الأرض.',
    'Mark Current Location': 'تحديد الموقع الحالي',
    'Undo Last': 'التراجع عن الأخير',
    'Clear All': 'مسح الكل',
    'Choose area display unit': 'اختر وحدة عرض المساحة',
    'Save Distance': 'حفظ المسافة',
    'Store this measured line locally and send it to the server as a distance record.':
        'احفظ هذا الخط المقاس محليًا وأرسله إلى الخادم كسجل مسافة.',
    'Contact phone': 'رقم هاتف التواصل',
    'Notes about this distance': 'ملاحظات حول هذه المسافة',
    'Point labels': 'تسميات النقاط',
    'Place is required.': 'المكان مطلوب.',
    'Save distance': 'حفظ المسافة',
    'Add location name and point label before saving.':
        'أضف اسم الموقع وتسمية النقطة قبل الحفظ.',
    'e.g. Home, Office, Farm Entrace': 'مثلاً: المنزل، المكتب، مدخل المزرعة',
    'Point label (e.g. A1, P1)': 'تسمية النقطة (مثل A1، P1)',
    'View area in': 'عرض المساحة بوحدة',
    '+ GPS': '+ GPS',
    'Long-press the map to add area points, or use + GPS for your current location.':
        'اضغط مطولًا على الخريطة لإضافة نقاط المساحة، أو استخدم + GPS لموقعك الحالي.',
    'Save area': 'حفظ المساحة',
    'Long-press anywhere on the map to place a marker':
        'اضغط مطولًا على أي مكان في الخريطة لوضع علامة',
    'Point added': 'تمت إضافة النقطة',
    '{count} points captured': 'النقاط الملتقطة: {count}',
    'Perimeter: {distance}': 'المحيط: {distance}',
    'Area: {area}': 'المساحة: {area}',
    'Optional. Rename boundary points for reference.':
        'اختياري. أعد تسمية نقاط الحدود لتسهيل الرجوع إليها.',
    'Point {number}': 'النقطة {number}',
    'Label': 'التسمية',
    'Field updated offline successfully. Sync queued.':
        'تم تحديث الأرض دون اتصال. المزامنة قيد الانتظار.',
    'Field saved offline successfully. Sync queued.':
        'تم حفظ الأرض دون اتصال. المزامنة قيد الانتظار.',
    'Save Area': 'حفظ المساحة',
    'Distance name or place': 'اسم المسافة أو المكان',
    '{count} points • {distance}': '{count} نقطة • {distance}',
    'Automatic': 'تلقائي',
    'Square metres (m²)': 'متر مربع (م²)',
    'Hectares (ha)': 'هكتارات (ha)',
    'Square kilometres (km²)': 'كيلومترات مربعة (كم²)',
    'Square feet (ft²)': 'أقدام مربعة (ft²)',
    'Acres (ac)': 'أفدنة (ac)',
    'Long-press map to add points': 'اضغط مطولًا على الخريطة لإضافة نقاط',
    '{count} pts · {distance}': '{count} نقاط · {distance}',
    'Long-press map to place marker': 'اضغط مطولًا على الخريطة لوضع علامة',
    'Long-press map or use + GPS to add area points':
        'اضغط مطولًا على الخريطة أو استخدم + GPS لإضافة نقاط المساحة',
    '{count} area pts · long-press to add more':
        '{count} نقاط مساحة · اضغط مطولًا لإضافة المزيد',
    'Location saved locally. Sync queued.':
        'تم حفظ الموقع محليًا. المزامنة قيد الانتظار.',
    'No current location available.': 'لا يوجد موقع حالي متاح.',
    'Marker deleted': 'تم حذف العلامة',
    'Add at least 2 points to save a distance.':
        'أضف نقطتين على الأقل لحفظ المسافة.',
    'Distance saved locally. Sync queued.':
        'تم حفظ المسافة محليًا. المزامنة قيد الانتظار.',
    'Road routing unavailable. Showing straight line.':
        'المسار عبر الطرق غير متاح. يُعرض خط مستقيم.',
    'Route updated from your current position.':
        'تم تحديث المسار من موقعك الحالي.',
    'Turn on the Field layer to add area points.':
        'فعّل طبقة الأرض لإضافة نقاط المساحة.',
    'Finding best route...': 'جارٍ البحث عن أفضل مسار…',
    'Switching map type...': 'جارٍ تغيير نوع الخريطة…',
    'UTM unavailable': 'إحداثيات UTM غير متاحة',
    '{reference} • Accuracy: {accuracy}': '{reference} • الدقة: {accuracy}',
    'Locating...': 'جارٍ تحديد الموقع…',
    'Waiting for GPS...': 'جارٍ انتظار GPS…',
    '{count} pts': '{count} نقاط',
    'Calculating...': 'جارٍ الحساب…',
    'Viewing: {name} · {count} pts': 'عرض: {name} · {count} نقاط',
    'Tools': 'الأدوات',
    'Location Services are off': 'خدمات الموقع متوقفة',
    'Location unavailable': 'الموقع غير متاح',
    'Use your current location?': 'هل تريد استخدام موقعك الحالي؟',
    'TaREF GPS needs Location Services to show your live position on the map, capture GPS points, guide navigation, measure routes, and attach coordinates to saved work. You can continue using the map and saved records without live GPS.':
        'يحتاج TaREF GPS إلى خدمات الموقع لعرض موقعك المباشر على الخريطة والتقاط نقاط GPS وإرشاد الملاحة وقياس المسارات وإرفاق الإحداثيات بالأعمال المحفوظة. يمكنك متابعة استخدام الخريطة والسجلات المحفوظة دون GPS مباشر.',
    'Location access is blocked for TaREF GPS. Enable it in Settings to use live map position, GPS point capture, navigation guidance, route measurement, and coordinate tagging. You can continue using the app without GPS.':
        'الوصول إلى الموقع محظور لتطبيق TaREF GPS. فعّله في الإعدادات لاستخدام الموقع المباشر والتقاط نقاط GPS وإرشاد الملاحة وقياس المسارات وإضافة الإحداثيات. يمكنك متابعة استخدام التطبيق دون GPS.',
    'TaREF GPS uses your current location only for GPS features such as live map position, point capture, navigation, distance tracking, and coordinate tagging. You can continue using the map without granting location access.':
        'يستخدم TaREF GPS موقعك الحالي فقط لميزات GPS مثل عرض الموقع المباشر والتقاط النقاط والملاحة وتتبع المسافة وإضافة الإحداثيات. يمكنك متابعة استخدام الخريطة دون منح إذن الموقع.',
    'View more': 'عرض المزيد',
    'File': 'ملف',
    'Full name': 'الاسم الكامل',
    'Name is required': 'الاسم مطلوب',
    'Email is required': 'البريد الإلكتروني مطلوب',
    'Phone number': 'رقم الهاتف',
    'Current password': 'كلمة المرور الحالية',
    'Current password is required': 'كلمة المرور الحالية مطلوبة',
    'New password': 'كلمة المرور الجديدة',
    'New password is required': 'كلمة المرور الجديدة مطلوبة',
    'Minimum 8 characters': '8 أحرف على الأقل',
    'Confirm new password': 'تأكيد كلمة المرور الجديدة',
    'Confirm your new password': 'أكد كلمة المرور الجديدة',
    'Passwords do not match': 'كلمتا المرور غير متطابقتين',
    'Update password': 'تحديث كلمة المرور',
    'Delete my account': 'حذف حسابي',
    'No email found': 'لم يتم العثور على بريد إلكتروني',
    'Verification code': 'رمز التحقق',
    'Send verification code': 'إرسال رمز التحقق',
    'Back to password step': 'العودة إلى خطوة كلمة المرور',
    '1 Request code': '1 طلب الرمز',
    '2 Confirm deletion': '2 تأكيد الحذف',
    'Open Settings': 'فتح الإعدادات',
    'Could not open Ardhi web app': 'تعذر فتح تطبيق Ardhi على الويب',
    'Could not open the app store.': 'تعذر فتح متجر التطبيقات.',
    'Could not open privacy policy': 'تعذر فتح سياسة الخصوصية',
    'Something went wrong. Please try again.':
        'حدث خطأ ما. يرجى المحاولة مرة أخرى.',
    'Enter your password': 'أدخل كلمة المرور',
    'Min. 8 characters': '8 أحرف على الأقل',
    'Repeat your password': 'أعد إدخال كلمة المرور',
    'Location is turned off': 'خدمات الموقع متوقفة',
    'Location access is blocked': 'الوصول إلى الموقع محظور',
    'Location access is off': 'الوصول إلى الموقع متوقف',
    'TaREF GPS needs Location Services for live coordinates, GPS point capture, navigation, distance tracking, and media geotagging. You can use the app without live GPS features.':
        'يحتاج TaREF GPS إلى خدمات الموقع لعرض الإحداثيات المباشرة والتقاط نقاط GPS والملاحة وتتبع المسافة وتحديد مواقع الوسائط. يمكنك استخدام التطبيق دون ميزات GPS المباشرة.',
    'Location access is blocked for TaREF GPS. Enable it in Settings to use live coordinates, GPS point capture, navigation, distance tracking, and media geotagging. You can use the app without live GPS features.':
        'الوصول إلى الموقع محظور لتطبيق TaREF GPS. فعّله من الإعدادات لاستخدام الإحداثيات المباشرة والتقاط نقاط GPS والملاحة وتتبع المسافة وتحديد مواقع الوسائط. يمكنك استخدام التطبيق دون ميزات GPS المباشرة.',
    'TaREF GPS uses location for live coordinates, GPS point capture, navigation, distance tracking, and media geotagging. You can use the app without live GPS features.':
        'يستخدم TaREF GPS الموقع للإحداثيات المباشرة والتقاط نقاط GPS والملاحة وتتبع المسافة وتحديد مواقع الوسائط. يمكنك استخدام التطبيق دون ميزات GPS المباشرة.',
    'Turn On Location': 'تشغيل خدمات الموقع',
    'Maybe Later': 'ربما لاحقًا',
    'My current location': 'موقعي الحالي',
    'My location {date}': 'موقعي {date}',
    'Lat/Long': 'خط العرض/الطول',
    'Lat / Lng': 'العرض / الطول',
    'E/N': 'الشرق/الشمال',
    'E': 'شرق',
    'N': 'شمال',
    '{count} selected': 'تم تحديد {count}',
    'General': 'عام',
    'All groups': 'كل المجموعات',
    'Cloud': 'السحابة',
    'Cloud land': 'أرض سحابية',
    'Cloud records only': 'السجلات السحابية فقط',
    'Cloud only': 'السحابة فقط',
    '3+ points': 'ثلاث نقاط أو أكثر',
    'Source': 'المصدر',
    'Saved location': 'موقع محفوظ',
    'Saved': 'المحفوظات',
    'Library': 'المكتبة',
    'Add manually': 'إضافة يدويًا',
    'Updating cloud records...': 'جارٍ تحديث السجلات السحابية…',
    'Loading more records...': 'جارٍ تحميل المزيد من السجلات…',
    'Failed to load coordinates. Check your connection and try again.':
        'تعذر تحميل الإحداثيات. تحقق من الاتصال وحاول مرة أخرى.',
    'Cloud deletion requires a valid session and land id.':
        'يتطلب الحذف من السحابة جلسة صالحة ومعرّف أرض.',
    'Unknown': 'غير معروف',
    'Saved to cloud': 'محفوظ في السحابة',
    'Saved {date}': 'حُفظ في {date}',
    'Updated {date}': 'حُدث في {date}',
    'Actions for {name}': 'إجراءات {name}',
    'Show less': 'عرض أقل',
    'Show all {count} points': 'عرض جميع النقاط الـ {count}',
    'Points ({count})': 'النقاط ({count})',
    'Point {count}': 'النقطة {count}',
    '{count} point': 'نقطة واحدة ({count})',
    '{count} points': '{count} نقاط',
    '{count} result': 'نتيجة واحدة ({count})',
    '{count} results': '{count} نتائج',
    'Showing latest {count} records. Use the web app to view older records.':
        'يتم عرض أحدث {count} سجل. استخدم تطبيق الويب لعرض السجلات الأقدم.',
    'Newest': 'الأحدث',
    'Oldest': 'الأقدم',
    'This will delete "{name}" from the server.':
        'سيتم حذف «{name}» من الخادم.',
    'This will delete {count} selected items. This action cannot be undone.':
        'سيتم حذف {count} من العناصر المحددة. لا يمكن التراجع عن هذا الإجراء.',
    'Deleted {count} selected item': 'تم حذف العنصر المحدد ({count})',
    'Deleted {count} selected items': 'تم حذف {count} من العناصر المحددة',
    'Enter valid latitude and longitude.': 'أدخل خط عرض وخط طول صالحين.',
    'Latitude must be between -90 and 90.':
        'يجب أن يكون خط العرض بين ‎-90 و90.',
    'Longitude must be between -180 and 180.':
        'يجب أن يكون خط الطول بين ‎-180 و180.',
    'Coordinates 0, 0 point to the Gulf of Guinea. Please enter real coordinates.':
        'تشير الإحداثيات 0، 0 إلى خليج غينيا. أدخل إحداثيات حقيقية.',
    'These coordinates are near 0,0 which is unlikely to be a real location.':
        'هذه الإحداثيات قريبة من 0،0، ومن غير المرجح أن تكون موقعًا حقيقيًا.',
    'Point {count} added.': 'تمت إضافة النقطة {count}.',
    'Enter valid easting and northing.': 'أدخل قيمتي الشرق والشمال بشكل صحيح.',
    'Zone number is required.': 'رقم المنطقة مطلوب.',
    'Zone must be between 1 and 60.': 'يجب أن تكون المنطقة بين 1 و60.',
    'Easting must be between 100,000 and 900,000 meters.':
        'يجب أن تكون قيمة الشرق بين 100,000 و900,000 متر.',
    'Northing must be between 0 and 10,000,000 meters.':
        'يجب أن تكون قيمة الشمال بين 0 و10,000,000 متر.',
    'Band letter must be C-X (excluding I and O).':
        'يجب أن يكون حرف النطاق بين C وX باستثناء I وO.',
    'Could not convert these UTM values to coordinates. Check your input.':
        'تعذر تحويل قيم UTM هذه إلى إحداثيات. تحقق من المدخلات.',
    'UTM values produce invalid coordinates. Please verify easting, northing, and zone.':
        'تنتج قيم UTM إحداثيات غير صالحة. تحقق من الشرق والشمال والمنطقة.',
    'Name is required.': 'الاسم مطلوب.',
    'Add at least one point.': 'أضف نقطة واحدة على الأقل.',
    'Saved and synced to cloud!': 'تم الحفظ والمزامنة مع السحابة!',
    'Saved locally. Cloud sync failed: {error}':
        'تم الحفظ محليًا. فشلت المزامنة السحابية: {error}',
    'Saved locally. Will sync when logged in.':
        'تم الحفظ محليًا. ستتم المزامنة بعد تسجيل الدخول.',
    'Failed to save: {error}': 'فشل الحفظ: {error}',
    'No saved locations': 'لا توجد مواقع محفوظة',
    'Your saved places will appear here.': 'ستظهر مواقعك المحفوظة هنا.',
    'No matching saved locations': 'لا توجد مواقع محفوظة مطابقة',
    'Try changing search text, filter, sort, or group.':
        'حاول تغيير نص البحث أو التصفية أو الترتيب أو المجموعة.',
    'All saved lands': 'جميع الأراضي المحفوظة',
    '3+ points only': 'ثلاث نقاط أو أكثر فقط',
    'Updated only': 'المحدّثة فقط',
    'Changes saved. They will sync when connected.':
        'تم حفظ التغييرات. ستتم مزامنتها عند الاتصال.',
    'Choose your preferred coordinate format to add points one by one.':
        'اختر صيغة الإحداثيات المفضلة لإضافة النقاط واحدة تلو الأخرى.',
    'Could not load more cloud records.':
        'تعذر تحميل المزيد من السجلات السحابية.',
    'Delete all': 'حذف الكل',
    'Delete all saved lands': 'حذف جميع الأراضي المحفوظة',
    'Delete all saved lands?': 'هل تريد حذف جميع الأراضي المحفوظة؟',
    'Delete cloud land?': 'هل تريد حذف الأرض السحابية؟',
    'Delete land': 'حذف الأرض',
    'Delete location?': 'هل تريد حذف الموقع؟',
    'Delete selected': 'حذف المحدد',
    'Delete selected locations?': 'هل تريد حذف المواقع المحددة؟',
    'Deleting...': 'جارٍ الحذف…',
    'Details': 'التفاصيل',
    'Distance': 'المسافة',
    'Edit cloud land': 'تعديل الأرض السحابية',
    'Edit metadata': 'تعديل البيانات الوصفية',
    'Enter coordinates in your preferred format':
        'أدخل الإحداثيات بالصيغة المفضلة لديك',
    'Enter location name (optional)': 'أدخل اسم الموقع (اختياري)',
    'Exit selection': 'إنهاء التحديد',
    'Filter': 'تصفية',
    'Go to': 'الانتقال إلى',
    'Go to map': 'الانتقال إلى الخريطة',
    'Group': 'المجموعة',
    'Group name': 'اسم المجموعة',
    'Group updated for selected items': 'تم تحديث مجموعة العناصر المحددة',
    'Help us improve TaREF': 'ساعدنا في تحسين TaREF',
    'Hemisphere': 'نصف الكرة',
    'Land deleted from cloud': 'تم حذف الأرض من السحابة',
    'Land deleted from cloud and app': 'تم حذف الأرض من السحابة والتطبيق',
    'Latitude': 'خط العرض',
    'Loading coordinates…': 'جارٍ تحميل الإحداثيات…',
    'Location details': 'تفاصيل الموقع',
    'Location not available yet': 'الموقع غير متاح بعد',
    'Location refreshed': 'تم تحديث الموقع',
    'Longitude': 'خط الطول',
    'Markers will be kept. This action cannot be undone.':
        'سيتم الاحتفاظ بالعلامات. لا يمكن التراجع عن هذا الإجراء.',
    'More': 'المزيد',
    'Name': 'الاسم',
    'Name *': 'الاسم *',
    'No cloud ID found for this record.':
        'لم يتم العثور على معرف سحابي لهذا السجل.',
    'No points found for guidance': 'لم يتم العثور على نقاط للإرشاد',
    'No points to display on map': 'لا توجد نقاط لعرضها على الخريطة',
    'Not now': 'ليس الآن',
    'Notes about this location': 'ملاحظات حول هذا الموقع',
    'Nothing to share': 'لا يوجد ما يمكن مشاركته',
    'Perimeter': 'المحيط',
    'Place': 'المكان',
    'Point': 'نقطة',
    'Point label (optional)': 'تسمية النقطة (اختياري)',
    'Points': 'النقاط',
    'Record type': 'نوع السجل',
    'Refresh': 'تحديث',
    'Rename': 'إعادة تسمية',
    'Rename location': 'إعادة تسمية الموقع',
    'Reset filters/sort/group': 'إعادة تعيين التصفية والترتيب والمجموعة',
    'Response saved. It will sync automatically.':
        'تم حفظ الرد. ستتم مزامنته تلقائيًا.',
    'Retry': 'إعادة المحاولة',
    'Route': 'مسار',
    'Selected items shared': 'تمت مشاركة العناصر المحددة',
    'Set group': 'تحديد المجموعة',
    'Set group for selected': 'تحديد مجموعة العناصر المحددة',
    'Share': 'مشاركة',
    'Share feedback': 'مشاركة الرأي',
    'Share selected': 'مشاركة المحدد',
    'Sign in again to delete cloud records.':
        'سجّل الدخول مجددًا لحذف السجلات السحابية.',
    'Sign in required to load cloud coordinates.':
        'يجب تسجيل الدخول لتحميل الإحداثيات السحابية.',
    'Sort': 'ترتيب',
    'Tell us what is working and what is difficult. It takes about a minute.':
        'أخبرنا بما يعمل جيدًا وما يصعب استخدامه. يستغرق ذلك نحو دقيقة.',
    'This action cannot be undone.': 'لا يمكن التراجع عن هذا الإجراء.',
    'This record has no coordinates available.':
        'لا توجد إحداثيات متاحة لهذا السجل.',
    'Type': 'النوع',
    'Type is determined by point count: 1 = Point, 2 = Distance, 3+ = Area':
        'يتحدد النوع بعدد النقاط: 1 = نقطة، 2 = مسافة، 3 أو أكثر = مساحة',
    'View details': 'عرض التفاصيل',
    'View on map': 'عرض على الخريطة',
    'Zone number': 'رقم المنطقة',
    'e.g. A1, Corner 1': 'مثل A1، الزاوية 1',
    'e.g. Dodoma, Tanzania': 'مثل دودوما، تنزانيا',
    'e.g. Farm boundary, Warehouse': 'مثل حدود المزرعة، المستودع',
    'Add coordinate points': 'إضافة نقاط الإحداثيات',
    'Add location manually': 'إضافة موقع يدويًا',
    'Add point': 'إضافة نقطة',
    'Added points': 'النقاط المضافة',
    'Area': 'المساحة',
    'Auto': 'تلقائي',
    'Band letter': 'حرف النطاق',
    'Contact number': 'رقم الاتصال',
    'Coordinates copied': 'تم نسخ الإحداثيات',
    'Created': 'تاريخ الإنشاء',
    'Description': 'الوصف',
    'UTM': 'UTM',
  };
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales.any(
    (supported) => supported.languageCode == locale.languageCode,
  );

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      SynchronousFuture<AppLocalizations>(
        AppLocalizations(
          AppLocalizations.supportedLocales.firstWhere(
            (supported) => supported.languageCode == locale.languageCode,
            orElse: () => const Locale('en'),
          ),
        ),
      );

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension AppLocalizationContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
