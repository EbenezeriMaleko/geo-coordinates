import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:hive/hive.dart';
import 'package:flutter/foundation.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/localization/locale_provider.dart';
import '../models/coordinate_format.dart';
import '../models/geodetic_datum.dart';
import '../models/reference_ellipsoid.dart';
import '../state/settings_provider.dart';
import '../state/land_map_notifier.dart';
import '../services/app_review_service.dart';
import '../services/survey_invitation.dart';
import 'user_survey_page.dart';
import '../../workspaces/workspace_provider.dart';
import '../../widget/profile_widget.dart';
import '../../widget/settings_sheet.dart';
import 'package:hugeicons/hugeicons.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final Future<PackageInfo> _packageInfoFuture;

  @override
  void initState() {
    super.initState();
    _packageInfoFuture = PackageInfo.fromPlatform();
  }

  static const Color _personalAccent = Color(0xFF001F3F);
  static const Color _companyAccent = Color(0xFF245B83);
  static const Color _pageBackground = Color(0xFFF7F7F8);
  static const Color _green = Color(0xFF1B7F4B);
  static const Color _greenSoft = Color(0xFFE6F5EC);
  static const Color _amber = Color(0xFFB26A00);
  static const Color _amberSoft = Color(0xFFFFF4E0);

  /// Sheets open above this page's Theme, so they take the accent explicitly.
  Color get _accent => ref.read(workspaceProvider).activeCompanyId != null
      ? _companyAccent
      : _personalAccent;

  @override
  Widget build(BuildContext context) {
    final selectedFormat = ref.watch(coordinateFormatProvider);
    final selectedUnit = ref.watch(distanceUnitProvider);
    final saveOriginalPhoto = ref.watch(saveOriginalPhotoProvider);
    final saveToGallery = ref.watch(saveToGalleryProvider);
    final selectedEllipsoid = ref.watch(referenceEllipsoidProvider);
    final selectedDatum = ref.watch(selectedDatumProvider);
    final isCompany = ref.watch(workspaceProvider).activeCompanyId != null;
    final accent = isCompany ? _companyAccent : _personalAccent;
    final baseTheme = Theme.of(context);
    final l10n = context.l10n;
    final unitLabel = selectedUnit == DistanceUnit.feet ? 'Feet' : 'Meters';

    return Theme(
      data: baseTheme.copyWith(
        colorScheme: baseTheme.colorScheme.copyWith(primary: accent),
      ),
      child: ColoredBox(
        color: _pageBackground,
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 32),
          children: [
            ProfileSection(
              title: l10n.t('App preferences'),
              children: [
                ProfileTile(
                  icon: HugeIcons.strokeRoundedLanguageSquare,
                  title: l10n.t('Language'),
                  subtitle: _languageLabel(ref.watch(localeProvider), l10n),
                  onTap: _showLanguageSelector,
                ),
                ProfileTile(
                  icon: HugeIcons.strokeRoundedRuler,
                  title: l10n.t('Units'),
                  subtitle: l10n.t(unitLabel),
                  onTap: _showDistanceUnitSelector,
                ),
              ],
            ),

            ProfileSection(
              title: l10n.t('Location Settings'),
              children: [
                ProfileTile(
                  icon: HugeIcons.strokeRoundedLocation01,
                  title: l10n.t('Coordinates format'),
                  subtitle: l10n.t(selectedFormat.displayName),
                  onTap: _showCoordinateFormatSelector,
                ),
                ProfileTile(
                  icon: HugeIcons.strokeRoundedGlobe02,
                  title: l10n.t('Geodetic datum'),
                  subtitle: selectedDatum == null
                      ? selectedEllipsoid.displayName
                      : l10n.t(selectedDatum.displayName),
                  onTap: _showReferenceEllipsoidSelector,
                ),
                ProfileTile(
                  icon: HugeIcons.strokeRoundedCompass01,
                  title: l10n.t('Compass north reference'),
                  subtitle: l10n.t(
                    _compassNorthLabel(ref.watch(compassNorthTypeProvider)),
                  ),
                  onTap: _showCompassNorthSelector,
                ),
              ],
            ),

            ProfileSection(
              title: l10n.t('Photo'),
              children: [
                ProfileSwitchTile(
                  icon: HugeIcons.strokeRoundedImage01,
                  title: l10n.t('Save original photo'),
                  subtitle: l10n.t(
                    'Save with no data on it. Useful for editing before sharing.',
                  ),
                  value: saveOriginalPhoto,
                  onChanged: (v) => ref
                      .read(saveOriginalPhotoProvider.notifier)
                      .setValue(v),
                ),
                ProfileSwitchTile(
                  icon: HugeIcons.strokeRoundedAlbum02,
                  title: l10n.t('Save to gallery'),
                  subtitle: l10n.t('Save image with data'),
                  value: saveToGallery,
                  onChanged: (v) =>
                      ref.read(saveToGalleryProvider.notifier).setValue(v),
                ),
              ],
            ),

            ProfileSection(
              title: l10n.t('Privacy & storage'),
              children: [
                ProfileTile(
                  icon: HugeIcons.strokeRoundedShield01,
                  title: l10n.t('Privacy policy'),
                  onTap: _openPrivacyPolicy,
                ),
                ProfileTile(
                  icon: HugeIcons.strokeRoundedDelete02,
                  title: l10n.t('Clear cache'),
                  subtitle: l10n.t('Remove cached data and temporary files'),
                  onTap: _clearCache,
                ),
              ],
            ),

            ProfileSection(
              title: l10n.t('Help & feedback'),
              children: [
                ProfileTile(
                  icon: HugeIcons.strokeRoundedMail01,
                  title: l10n.t('Contact us'),
                  subtitle: l10n.t(
                    'Send suggestions or report a bug. We appreciate your feedback.',
                  ),
                  onTap: _openContactUsPage,
                ),
                ProfileTile(
                  icon: HugeIcons.strokeRoundedMessage01,
                  title: l10n.t('Share your experience'),
                  subtitle: l10n.t('Tell us what works and what is difficult.'),
                  onTap: _openSurveyPage,
                ),
                if (kDebugMode)
                  ProfileTile(
                    icon: HugeIcons.strokeRoundedBug01,
                    title: l10n.t('Preview survey invitation'),
                    subtitle: l10n.t('Debug only. Open Library after tapping.'),
                    onTap: _previewSurveyInvitation,
                  ),
                ProfileTile(
                  icon: HugeIcons.strokeRoundedStar,
                  title: l10n.t('Rate our app'),
                  subtitle: l10n.t('Leave a rating or review in the app store.'),
                  onTap: _openStoreReview,
                ),
              ],
            ),

            ProfileSection(
              title: l10n.t('About'),
              children: [
                FutureBuilder<PackageInfo>(
                  future: _packageInfoFuture,
                  builder: (context, snapshot) {
                    final info = snapshot.data;
                    final text =
                        snapshot.connectionState == ConnectionState.waiting
                        ? l10n.t('Loading version...')
                        : info == null
                        ? l10n.t('Version unavailable')
                        : '${info.version}+${info.buildNumber}';
                    return ProfileTile(
                      icon: HugeIcons.strokeRoundedInformationCircle,
                      title: l10n.t('Version'),
                      subtitle: text,
                      onTap: _showVersionDetails,
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _languageLabel(Locale? locale, AppLocalizations l10n) {
    if (locale == null) return l10n.t('System default');
    if (locale.languageCode == 'fr') return l10n.t('French');
    if (locale.languageCode == 'ar') return l10n.t('Arabic');
    return l10n.t('English');
  }

  // ── Language ──────────────────────────────────────────────────

  void _showLanguageSelector() {
    final current = ref.read(localeProvider);
    final l10n = context.l10n;
    final accent = _accent;

    Future<void> choose(BuildContext sheetContext, Locale? locale) async {
      await ref.read(localeProvider.notifier).setLocale(locale);
      if (mounted && sheetContext.mounted) Navigator.pop(sheetContext);
    }

    showAppSheet<void>(
      context,
      (sheetContext) => SheetFrame(
        accent: accent,
        icon: HugeIcons.strokeRoundedLanguageSquare,
        title: l10n.t('Language'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetOptionTile(
              accent: accent,
              leading: SheetLeadingIcon(
                icon: HugeIcons.strokeRoundedSmartPhone01,
                accent: accent,
                selected: current == null,
              ),
              title: l10n.t('System default'),
              selected: current == null,
              onTap: () => choose(sheetContext, null),
            ),
            SheetOptionTile(
              accent: accent,
              leading: SheetLeadingText(
                'EN',
                accent: accent,
                selected: current?.languageCode == 'en',
              ),
              title: l10n.t('English'),
              selected: current?.languageCode == 'en',
              onTap: () => choose(sheetContext, const Locale('en')),
            ),
            SheetOptionTile(
              accent: accent,
              leading: SheetLeadingText(
                'FR',
                accent: accent,
                selected: current?.languageCode == 'fr',
              ),
              title: l10n.t('French'),
              selected: current?.languageCode == 'fr',
              onTap: () => choose(sheetContext, const Locale('fr')),
            ),
            SheetOptionTile(
              accent: accent,
              leading: SheetLeadingText(
                'AR',
                accent: accent,
                selected: current?.languageCode == 'ar',
              ),
              title: l10n.t('Arabic'),
              selected: current?.languageCode == 'ar',
              onTap: () => choose(sheetContext, const Locale('ar')),
            ),
          ],
        ),
      ),
    );
  }

  // ── Version ───────────────────────────────────────────────────

  void _showVersionDetails() {
    final l10n = context.l10n;
    final accent = _accent;
    showAppSheet<void>(
      context,
      (sheetContext) => SheetFrame(
        accent: accent,
        icon: HugeIcons.strokeRoundedInformationCircle,
        title: l10n.t('Version'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: FutureBuilder<PackageInfo>(
            future: _packageInfoFuture,
            builder: (context, snapshot) {
              final info = snapshot.data;
              final loading =
                  snapshot.connectionState == ConnectionState.waiting;
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: _pageBackground,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE8ECF0)),
                ),
                child: Column(
                  children: [
                    Text(
                      info == null
                          ? l10n.t('Loading version...')
                          : info.version,
                      style: TextStyle(
                        fontSize: info == null ? 15 : 30,
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                    if (info != null) ...[
                      const SizedBox(height: 8),
                      SheetBadge(
                        '+${info.buildNumber}',
                        fg: accent,
                        bg: accent.withValues(alpha: 0.10),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      loading
                          ? l10n.t(
                              'Reading build metadata from the app package...',
                            )
                          : l10n.t(
                              'This comes from the installed app metadata.',
                            ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ── Clear cache ───────────────────────────────────────────────

  Future<void> _clearCache() async {
    final l10n = context.l10n;
    final confirmed = await showAppSheet<bool>(
      context,
      (_) => ConfirmSheet(
        accent: _accent,
        destructive: true,
        icon: HugeIcons.strokeRoundedDelete02,
        title: l10n.t('Clear cache?'),
        body: l10n.t(
          'This will clear all cached data including images, temporary files, and app cache storage. Your saved locations will not be affected.',
        ),
        confirmLabel: l10n.t('Clear'),
        cancelLabel: l10n.t('Cancel'),
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);

    try {
      // Clear Flutter image cache
      imageCache.clear();
      imageCache.clearLiveImages();

      // Calculate freed space
      int freedBytes = 0;

      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        freedBytes += _getTotalSize(tempDir);
        await tempDir.delete(recursive: true);
        await tempDir.create(recursive: true);
      }

      try {
        final cacheDir = await getApplicationCacheDirectory();
        if (cacheDir.existsSync()) {
          freedBytes += _getTotalSize(cacheDir);
          await cacheDir.delete(recursive: true);
          await cacheDir.create(recursive: true);
        }
      } catch (_) {}

      if (!mounted) return;

      final freedMB = (freedBytes / (1024 * 1024)).toStringAsFixed(2);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            freedBytes > 0
                ? l10n.t(
                    'Cache cleared successfully (~{size} MB freed)',
                    params: {'size': freedMB},
                  )
                : l10n.t('Cache cleared successfully'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n.t('Error clearing cache: {error}', params: {'error': '$e'}),
          ),
        ),
      );
    }
  }

  // Helper method to calculate total size of directory
  int _getTotalSize(Directory dir) {
    int totalSize = 0;
    try {
      if (dir.existsSync()) {
        dir.listSync(recursive: true).forEach((file) {
          if (file is File) {
            totalSize += file.lengthSync();
          }
        });
      }
    } catch (_) {}
    return totalSize;
  }

  // ── Contact / survey / store / privacy ────────────────────────

  Future<void> _openContactUsPage() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _ContactDialog(accent: _accent),
    );
  }

  Future<void> _openSurveyPage() async {
    final saved = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const UserSurveyPage()));
    if (!mounted || saved != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.t('Response saved. It will sync automatically.'),
        ),
      ),
    );
  }

  Future<void> _previewSurveyInvitation() async {
    await SurveyInvitation(Hive.box('landbox')).requestDebugPreview();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.t(
            'Preview ready. Open Library. Submitting the form sends a real response.',
          ),
        ),
      ),
    );
  }

  Future<void> _openStoreReview() async {
    var opened = false;
    try {
      opened = await AppReviewService(Hive.box('landbox')).openStoreListing();
    } catch (_) {
      opened = false;
    }
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.t('Could not open the app store.'))),
    );
  }

  Future<void> _openPrivacyPolicy() async {
    final uri = Uri.parse('https://www.databenki.com/privacy/');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (ok) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.t('Could not open privacy policy'))),
    );
  }

  // ── Coordinates format ────────────────────────────────────────

  void _showCoordinateFormatSelector() {
    final current = ref.read(coordinateFormatProvider);
    final l10n = context.l10n;
    final accent = _accent;
    showAppSheet<void>(
      context,
      (sheetContext) => SheetFrame(
        accent: accent,
        icon: HugeIcons.strokeRoundedLocation01,
        title: l10n.t('Coordinates format'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final format in CoordinateFormat.values)
              SheetOptionTile(
                accent: accent,
                leading: SheetLeadingIcon(
                  icon: HugeIcons.strokeRoundedLocation01,
                  accent: accent,
                  selected: format == current,
                ),
                title: l10n.t(format.displayName),
                subtitle: _getFormatExample(format),
                selected: format == current,
                onTap: () {
                  ref.read(coordinateFormatProvider.notifier).setFormat(format);
                  Navigator.pop(sheetContext);
                },
              ),
          ],
        ),
      ),
    );
  }

  // ── Units ─────────────────────────────────────────────────────

  void _showDistanceUnitSelector() {
    final current = ref.read(distanceUnitProvider);
    final l10n = context.l10n;
    final accent = _accent;
    showAppSheet<void>(
      context,
      (sheetContext) => SheetFrame(
        accent: accent,
        icon: HugeIcons.strokeRoundedRuler,
        title: l10n.t('Units'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetOptionTile(
              accent: accent,
              leading: SheetLeadingText(
                'm',
                accent: accent,
                selected: current == DistanceUnit.meters,
              ),
              title: l10n.t('Meters'),
              subtitle: l10n.t('Use meters (m)'),
              selected: current == DistanceUnit.meters,
              onTap: () {
                ref
                    .read(distanceUnitProvider.notifier)
                    .setUnit(DistanceUnit.meters);
                Navigator.pop(sheetContext);
              },
            ),
            SheetOptionTile(
              accent: accent,
              leading: SheetLeadingText(
                'ft',
                accent: accent,
                selected: current == DistanceUnit.feet,
              ),
              title: l10n.t('Feet'),
              subtitle: l10n.t('Use feet (ft)'),
              selected: current == DistanceUnit.feet,
              onTap: () {
                ref
                    .read(distanceUnitProvider.notifier)
                    .setUnit(DistanceUnit.feet);
                Navigator.pop(sheetContext);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Geodetic datum ────────────────────────────────────────────

  /// The original strings carry a leading bullet (" • Approximate").
  /// Strip it so the text can be shown inside a badge, keeping translations.
  String _badgeText(String translated) => translated.replaceAll('•', '').trim();

  void _showReferenceEllipsoidSelector() {
    final currentEllipsoid = ref.read(referenceEllipsoidProvider);
    final currentDatum = ref.read(selectedDatumProvider);
    final currentLocation = ref.read(landMapProvider).current;
    final accent = _accent;
    final datums = ReferenceEllipsoid.values
        .expand(GeodeticDatumRegistry.forEllipsoid)
        .toList();
    if (currentLocation != null) {
      datums.sort((left, right) {
        final byArea = (right.isValidAt(currentLocation) ? 1 : 0).compareTo(
          left.isValidAt(currentLocation) ? 1 : 0,
        );
        return byArea != 0
            ? byArea
            : left.accuracyMeters.compareTo(right.accuracyMeters);
      });
    }
    final datumlessEllipsoids = ReferenceEllipsoid.values
        .where(
          (ellipsoid) =>
              ellipsoid != ReferenceEllipsoid.wgs84 &&
              GeodeticDatumRegistry.forEllipsoid(ellipsoid).isEmpty,
        )
        .toList();

    showAppSheet<void>(
      context,
      (sheetContext) {
        final l10n = sheetContext.l10n;
        final wgsSelected =
            currentDatum == null &&
            currentEllipsoid == ReferenceEllipsoid.wgs84;
        return SheetFrame(
          accent: accent,
          icon: HugeIcons.strokeRoundedGlobe02,
          title: l10n.t('Select datum'),
          subtitle: l10n.t(
            'Choose the datum used by your survey. Its reference ellipsoid is shown below the datum name.',
          ),
          height: MediaQuery.of(sheetContext).size.height * 0.8,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              SheetOptionTile(
                accent: accent,
                leading: SheetLeadingText(
                  'WGS',
                  accent: accent,
                  selected: wgsSelected,
                ),
                title: ReferenceEllipsoid.wgs84.displayName,
                subtitle: l10n.t(
                  'WGS 84 ellipsoid • Global reference system (default; valid everywhere)',
                ),
                selected: wgsSelected,
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _handleEllipsoidOrDatumChange(
                    ReferenceEllipsoid.wgs84,
                    null,
                  );
                },
              ),
              for (final datum in datums)
                () {
                  final isSelected = currentDatum?.id == datum.id;
                  final validHere =
                      currentLocation != null &&
                      datum.isValidAt(currentLocation);
                  return SheetOptionTile(
                    accent: accent,
                    leading: SheetLeadingIcon(
                      icon: validHere
                          ? HugeIcons.strokeRoundedLocation01
                          : HugeIcons.strokeRoundedGlobe02,
                      accent: accent,
                      selected: isSelected,
                    ),
                    title: l10n.t(datum.displayName),
                    subtitle: l10n.t(
                      '{ellipsoid} ellipsoid • {area}\nEPSG:{code} • {accuracy} m accuracy',
                      params: {
                        'ellipsoid': datum.parentEllipsoid.displayName,
                        'area': l10n.t(datum.areaOfUse),
                        'code': '${datum.epsgOperationCode}',
                        'accuracy': datum.accuracyMeters.toStringAsFixed(0),
                      },
                    ),
                    badges: [
                      if (validHere)
                        SheetBadge(
                          _badgeText(l10n.t(' • Valid here')),
                          fg: _green,
                          bg: _greenSoft,
                        ),
                      if (datum.isApproximate)
                        SheetBadge(
                          _badgeText(l10n.t(' • Approximate')),
                          fg: _amber,
                          bg: _amberSoft,
                        ),
                    ],
                    selected: isSelected,
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      await _handleEllipsoidOrDatumChange(
                        datum.parentEllipsoid,
                        datum,
                      );
                    },
                  );
                }(),
              if (datumlessEllipsoids.isNotEmpty) ...[
                SheetSectionLabel(
                  l10n.t('REFERENCE / ELLIPSOID-ONLY OPTIONS'),
                ),
                for (final ellipsoid in datumlessEllipsoids)
                  () {
                    final isSelected =
                        currentDatum == null && currentEllipsoid == ellipsoid;
                    return SheetOptionTile(
                      accent: accent,
                      leading: SheetLeadingIcon(
                        icon: HugeIcons.strokeRoundedGlobe02,
                        accent: accent,
                        selected: isSelected,
                      ),
                      title: ellipsoid.displayName,
                      subtitle: l10n.t(
                        '{ellipsoid} ellipsoid • No verified datum transformation; ellipsoid-shape-only conversion',
                        params: {'ellipsoid': ellipsoid.displayName},
                      ),
                      selected: isSelected,
                      onTap: () async {
                        Navigator.of(sheetContext).pop();
                        await _handleEllipsoidOrDatumChange(ellipsoid, null);
                      },
                    );
                  }(),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Re-derives secondary coordinates from canonical WGS84 values.
  Future<void> _handleEllipsoidOrDatumChange(
    ReferenceEllipsoid newEllipsoid,
    GeodeticDatum? newDatum,
  ) async {
    try {
      final ellipsoidNotifier = ref.read(referenceEllipsoidProvider.notifier);
      final datumNotifier = ref.read(selectedDatumProvider.notifier);
      final currentEllipsoid = ref.read(referenceEllipsoidProvider);
      final currentDatum = ref.read(selectedDatumProvider);

      if (newEllipsoid == currentEllipsoid &&
          newDatum?.id == currentDatum?.id) {
        return;
      }

      final landMapNotifier = ref.read(landMapProvider.notifier);
      landMapNotifier.deriveDisplayCoordinates(
        newEllipsoid,
        newDatum,
        previousEllipsoid: currentEllipsoid,
        previousDatum: currentDatum,
      );
      await ellipsoidNotifier.setEllipsoid(newEllipsoid);
      await datumNotifier.setDatum(newDatum);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.t(
              'Coordinates now shown in {datum}',
              params: {
                'datum': newDatum == null
                    ? newEllipsoid.displayName
                    : context.l10n.t(newDatum.displayName),
              },
            ),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.t(
              'Error changing coordinate display: {error}',
              params: {'error': '$e'},
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ── Compass ───────────────────────────────────────────────────

  String _compassNorthLabel(CompassNorthType type) {
    switch (type) {
      case CompassNorthType.magnetic:
        return 'Magnetic North';
      case CompassNorthType.trueNorth:
        return 'True North (geographic)';
    }
  }

  void _showCompassNorthSelector() {
    final current = ref.read(compassNorthTypeProvider);
    final l10n = context.l10n;
    final accent = _accent;
    showAppSheet<void>(
      context,
      (sheetContext) => SheetFrame(
        accent: accent,
        icon: HugeIcons.strokeRoundedCompass01,
        title: l10n.t('Compass north reference'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetOptionTile(
              accent: accent,
              leading: SheetLeadingIcon(
                icon: HugeIcons.strokeRoundedCompass01,
                accent: accent,
                selected: current == CompassNorthType.magnetic,
              ),
              title: l10n.t('Magnetic North'),
              subtitle: l10n.t(
                'Uses raw compass sensor reading. No correction applied.',
              ),
              selected: current == CompassNorthType.magnetic,
              onTap: () {
                ref
                    .read(compassNorthTypeProvider.notifier)
                    .setNorthType(CompassNorthType.magnetic);
                Navigator.pop(sheetContext);
              },
            ),
            SheetOptionTile(
              accent: accent,
              leading: SheetLeadingIcon(
                icon: HugeIcons.strokeRoundedGlobe02,
                accent: accent,
                selected: current == CompassNorthType.trueNorth,
              ),
              title: l10n.t('True North'),
              subtitle: l10n.t(
                'Corrects for magnetic declination to point to geographic north.',
              ),
              selected: current == CompassNorthType.trueNorth,
              onTap: () {
                ref
                    .read(compassNorthTypeProvider.notifier)
                    .setNorthType(CompassNorthType.trueNorth);
                Navigator.pop(sheetContext);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _getFormatExample(CoordinateFormat format) {
    const lat = -6.7924;
    const lon = 39.2083;
    return context.l10n.t(
      'Example: {coordinates}',
      params: {'coordinates': CoordinateFormatter.format(lat, lon, format)},
    );
  }
}

// ── Contact dialog ─────────────────────────────────────────────────

class _ContactDialog extends StatefulWidget {
  const _ContactDialog({required this.accent});
  final Color accent;

  @override
  State<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<_ContactDialog> {
  final _controller = TextEditingController();
  bool _isSending = false;
  static const String _supportEmail = 'databenki.group@gmail.com';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final message = _controller.text.trim();
    if (message.isEmpty) return;
    final l10n = context.l10n;

    setState(() => _isSending = true);

    try {
      final info = await PackageInfo.fromPlatform();
      final version = '${info.version}+${info.buildNumber}';

      // Gather safe device details (no PII, no advertising IDs)
      final deviceInfo = DeviceInfoPlugin();
      String deviceDetails = '';
      if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        deviceDetails =
            '${l10n.t('Device')}: ${android.manufacturer} ${android.model}\n'
            'Android: ${android.version.release} (SDK ${android.version.sdkInt})\n'
            '${l10n.t('Product')}: ${android.product}';
      } else if (Platform.isIOS) {
        final ios = await deviceInfo.iosInfo;
        deviceDetails =
            '${l10n.t('Device')}: ${ios.utsname.machine}\n'
            'iOS: ${ios.systemVersion}\n'
            '${l10n.t('Model')}: ${ios.model}';
      }

      final subject = Uri.encodeComponent(l10n.t('[TaREF GPS] Feedback'));
      final body = Uri.encodeComponent(
        '$message\n\n'
        '---\n'
        '${l10n.t('App version')}: $version\n'
        '$deviceDetails\n'
        '${l10n.t('Platform')}: ${Platform.operatingSystem}',
      );

      final uri = Uri.parse(
        'mailto:$_supportEmail?subject=$subject&body=$body',
      );

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!mounted) return;

      if (launched) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.t('Email app opened — tap Send to submit.'),
            ),
          ),
        );
      } else {
        // No email app — copy to clipboard fallback
        await Clipboard.setData(ClipboardData(text: message));
        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.t(
                'No email app found. Message copied — send it to {email}',
                params: {'email': _supportEmail},
              ),
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.t('Something went wrong. Please try again.'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;

    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: c, width: w),
    );

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  alignment: Alignment.center,
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedMail01,
                    color: accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.t('Send feedback'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.l10n.t('We read every message'),
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const HugeIcon(
                    icon: HugeIcons.strokeRoundedCancel01,
                    color: Colors.black45,
                    size: 20,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Message field
            TextField(
              controller: _controller,
              minLines: 4,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              autofocus: true,
              decoration: InputDecoration(
                hintText: context.l10n.t(
                  'Tell us what\'s on your mind — a bug, suggestion, or question…',
                ),
                hintStyle: const TextStyle(
                  color: Colors.black38,
                  fontSize: 13.5,
                  height: 1.5,
                ),
                filled: true,
                fillColor: const Color(0xFFF7F7F8),
                border: border(const Color(0xFFE8ECF0)),
                enabledBorder: border(const Color(0xFFE8ECF0)),
                focusedBorder: border(accent, 1.6),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),

            const SizedBox(height: 16),

            // Send button
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isSending ? null : _send,
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: _isSending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const HugeIcon(
                        icon: HugeIcons.strokeRoundedSent,
                        color: Colors.white,
                        size: 18,
                      ),
                label: Text(
                  context.l10n.t('Send'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}