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

import '../../auth/models/auth_models.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/ui/account_page.dart';
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

  @override
  Widget build(BuildContext context) {
    final selectedFormat = ref.watch(coordinateFormatProvider);
    final selectedUnit = ref.watch(distanceUnitProvider);
    final saveOriginalPhoto = ref.watch(saveOriginalPhotoProvider);
    final saveToGallery = ref.watch(saveToGalleryProvider);
    final photoQuality = ref.watch(photoQualityProvider);
    final captureMode = ref.watch(photoCaptureModeProvider);
    final selectedEllipsoid = ref.watch(referenceEllipsoidProvider);
    final selectedDatum = ref.watch(selectedDatumProvider);
    final session = ref.watch(authSessionProvider);
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final unitLabel = selectedUnit == DistanceUnit.feet ? 'Feet' : 'Meters';
    final accountSubtitle = _accountSubtitle(session);

    return ColoredBox(
      color: Colors.white,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _sectionHeader(l10n.t('Cloud synchronization'), theme),
          _item(
            title: l10n.t('Account'),
            subtitle: accountSubtitle,
            onTap: _openAccountPage,
          ),
          _sectionDivider(),

          _item(
            title: l10n.t('Language'),
            subtitle: _languageLabel(ref.watch(localeProvider), l10n),
            onTap: _showLanguageSelector,
          ),
          _sectionDivider(),

          _sectionHeader(l10n.t('Location Settings'), theme),
          _item(
            title: l10n.t('Coordinates format'),
            subtitle: l10n.t(selectedFormat.displayName),
            onTap: _showCoordinateFormatSelector,
          ),

          _item(
            title: l10n.t('Geodetic datum'),
            subtitle: selectedDatum == null
                ? selectedEllipsoid.displayName
                : l10n.t(selectedDatum.displayName),
            onTap: _showReferenceEllipsoidSelector,
          ),

          _item(
            title: l10n.t('Compass north reference'),
            subtitle: l10n.t(
              _compassNorthLabel(ref.watch(compassNorthTypeProvider)),
            ),
            onTap: _showCompassNorthSelector,
          ),

          _sectionDivider(),

          _item(
            title: l10n.t('Units'),
            subtitle: l10n.t(unitLabel),
            onTap: _showDistanceUnitSelector,
          ),
          _sectionDivider(),
          _sectionHeader(l10n.t('Photo'), theme),
          _switchItem(
            title: l10n.t('Save original photo'),
            subtitle: l10n.t(
              'Save with no data on it. Useful for editing before sharing.',
            ),
            value: saveOriginalPhoto,
            onChanged: (value) =>
                ref.read(saveOriginalPhotoProvider.notifier).setValue(value),
          ),
          _switchItem(
            title: l10n.t('Save to gallery'),
            subtitle: l10n.t('Save image with data'),
            value: saveToGallery,
            onChanged: (value) =>
                ref.read(saveToGalleryProvider.notifier).setValue(value),
          ),

          // _item(
          //   title: 'Image quality',
          //   subtitle: _photoQualityLabel(photoQuality),
          //   onTap: _showPhotoQualitySelector,
          // ),
          // _item(
          //   title: 'Capture mode',
          //   subtitle: _captureModeLabel(captureMode),
          //   onTap: _showCaptureModeSelector,
          // ),
          _sectionDivider(),

          _sectionHeader(l10n.t('Other'), theme),
          _item(title: l10n.t('Privacy policy'), onTap: _openPrivacyPolicy),
          _sectionDivider(),

          _sectionHeader(l10n.t('Cache'), theme),
          _item(
            title: l10n.t('Clear cache'),
            subtitle: l10n.t('Remove cached data and temporary files'),
            onTap: _clearCache,
          ),
          _sectionDivider(),

          _sectionHeader(l10n.t('Information'), theme),
          _item(
            title: l10n.t('Contact us'),
            subtitle: l10n.t(
              'Send suggestions or report a bug. We appreciate your feedback.',
            ),
            onTap: _openContactUsPage,
          ),
          _item(
            title: l10n.t('Share your experience'),
            subtitle: l10n.t('Tell us what works and what is difficult.'),
            onTap: _openSurveyPage,
          ),
          if (kDebugMode)
            _item(
              title: l10n.t('Preview survey invitation'),
              subtitle: l10n.t('Debug only. Open Library after tapping.'),
              onTap: _previewSurveyInvitation,
            ),
          _item(
            title: l10n.t('Rate our app'),
            subtitle: l10n.t('Leave a rating or review in the app store.'),
            onTap: _openStoreReview,
          ),
          _item(
            title: l10n.t('Version'),
            subtitleWidget: FutureBuilder<PackageInfo>(
              future: _packageInfoFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Text(
                    l10n.t('Loading version...'),
                    style: TextStyle(fontSize: 14, color: Colors.black54),
                  );
                }

                final info = snapshot.data;
                if (info == null) {
                  return Text(
                    l10n.t('Version unavailable'),
                    style: TextStyle(fontSize: 14, color: Colors.black54),
                  );
                }

                return Text(
                  '${info.version}+${info.buildNumber}',
                  style: const TextStyle(fontSize: 14, color: Colors.black54),
                );
              },
            ),
            onTap: _showVersionDetails,
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 6),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _item({
    required String title,
    String? subtitle,
    Widget? subtitleWidget,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            if (subtitleWidget != null) ...[
              const SizedBox(height: 3),
              subtitleWidget,
            ] else if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black54,
                  height: 1.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _switchItem({
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Checkbox(
            value: value,
            onChanged: (newValue) => onChanged(newValue ?? false),
            side: const BorderSide(color: Colors.black45, width: 2),
            activeColor: const Color(0xFF0C8A8C),
          ),
        ],
      ),
    );
  }

  Widget _sectionDivider() {
    return Divider(height: 1, color: Colors.grey.shade300);
  }

  String _languageLabel(Locale? locale, AppLocalizations l10n) {
    if (locale == null) return l10n.t('System default');
    if (locale.languageCode == 'fr') return l10n.t('French');
    if (locale.languageCode == 'ar') return l10n.t('Arabic');
    return l10n.t('English');
  }

  void _showLanguageSelector() {
    final current = ref.read(localeProvider);
    final l10n = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Text(
              l10n.t('Language'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            ListTile(
              title: Text(l10n.t('System default')),
              trailing: current == null
                  ? const Icon(Icons.check_circle, color: Color(0xFF0C8A8C))
                  : const Icon(Icons.circle_outlined),
              onTap: () async {
                await ref.read(localeProvider.notifier).setLocale(null);
                if (mounted) Navigator.pop(context);
              },
            ),
            ListTile(
              title: Text(l10n.t('English')),
              trailing: current?.languageCode == 'en'
                  ? const Icon(Icons.check_circle, color: Color(0xFF0C8A8C))
                  : const Icon(Icons.circle_outlined),
              onTap: () async {
                await ref
                    .read(localeProvider.notifier)
                    .setLocale(const Locale('en'));
                if (mounted) Navigator.pop(context);
              },
            ),
            ListTile(
              title: Text(l10n.t('French')),
              trailing: current?.languageCode == 'fr'
                  ? const Icon(Icons.check_circle, color: Color(0xFF0C8A8C))
                  : const Icon(Icons.circle_outlined),
              onTap: () async {
                await ref
                    .read(localeProvider.notifier)
                    .setLocale(const Locale('fr'));
                if (mounted) Navigator.pop(context);
              },
            ),
            ListTile(
              title: Text(l10n.t('Arabic')),
              trailing: current?.languageCode == 'ar'
                  ? const Icon(Icons.check_circle, color: Color(0xFF0C8A8C))
                  : const Icon(Icons.circle_outlined),
              onTap: () async {
                await ref
                    .read(localeProvider.notifier)
                    .setLocale(const Locale('ar'));
                if (mounted) Navigator.pop(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showVersionDetails() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: FutureBuilder<PackageInfo>(
              future: _packageInfoFuture,
              builder: (context, snapshot) {
                final info = snapshot.data;
                final versionText = info == null
                    ? context.l10n.t('Loading version...')
                    : info.version;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.t('Version'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      versionText,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.connectionState == ConnectionState.waiting
                          ? context.l10n.t(
                              'Reading build metadata from the app package...',
                            )
                          : context.l10n.t(
                              'This comes from the installed app metadata.',
                            ),
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _clearCache() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.t('Clear cache?')),
        content: Text(
          context.l10n.t(
            'This will clear all cached data including images, temporary files, and app cache storage. Your saved locations will not be affected.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.t('Cancel')),
          ),
          TextButton(
            onPressed: () async {
              final l10n = context.l10n;
              Navigator.pop(context);

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
                      l10n.t(
                        'Error clearing cache: {error}',
                        params: {'error': '$e'},
                      ),
                    ),
                  ),
                );
              }
            },
            child: Text(
              context.l10n.t('Clear'),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
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

  String _accountSubtitle(AuthSession session) {
    final user = session.user;
    final fullName = user?.name.trim() ?? '';
    final email = user?.email.trim() ?? '';

    if (fullName.isNotEmpty && email.isNotEmpty) {
      return '$fullName\n$email';
    }
    if (fullName.isNotEmpty) {
      return '$fullName\n${context.l10n.t('Signed in')}';
    }
    if (email.isNotEmpty) {
      return '$email\n${context.l10n.t('Signed in')}';
    }
    return context.l10n.t(
      'Sign in only when you want to sync data to the server.',
    );
  }

  Future<void> _openAccountPage() async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute<void>(builder: (_) => const AccountPage()));
  }

  Future<void> _openContactUsPage() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (_) => const _ContactDialog(),
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

  void _showCoordinateFormatSelector() {
    final current = ref.read(coordinateFormatProvider);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Text(
              context.l10n.t('Coordinates format'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            ...CoordinateFormat.values.map((format) {
              final isSelected = format == current;
              return ListTile(
                title: Text(context.l10n.t(format.displayName)),
                subtitle: Text(_getFormatExample(format)),
                trailing: isSelected
                    ? const Icon(Icons.check_circle, color: Color(0xFF0C8A8C))
                    : const Icon(Icons.circle_outlined),
                onTap: () {
                  ref.read(coordinateFormatProvider.notifier).setFormat(format);
                  Navigator.pop(context);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showDistanceUnitSelector() {
    final current = ref.read(distanceUnitProvider);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Text(
              context.l10n.t('Units'),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            ListTile(
              title: Text(context.l10n.t('Meters')),
              subtitle: Text(context.l10n.t('Use meters (m)')),
              trailing: current == DistanceUnit.meters
                  ? const Icon(Icons.check_circle, color: Color(0xFF0C8A8C))
                  : const Icon(Icons.circle_outlined),
              onTap: () {
                ref
                    .read(distanceUnitProvider.notifier)
                    .setUnit(DistanceUnit.meters);
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: Text(context.l10n.t('Feet')),
              subtitle: Text(context.l10n.t('Use feet (ft)')),
              trailing: current == DistanceUnit.feet
                  ? const Icon(Icons.check_circle, color: Color(0xFF0C8A8C))
                  : const Icon(Icons.circle_outlined),
              onTap: () {
                ref
                    .read(distanceUnitProvider.notifier)
                    .setUnit(DistanceUnit.feet);
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showReferenceEllipsoidSelector() {
    final currentEllipsoid = ref.read(referenceEllipsoidProvider);
    final currentDatum = ref.read(selectedDatumProvider);
    final currentLocation = ref.read(landMapProvider).current;
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.75,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Text(
                sheetContext.l10n.t('Select datum'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Text(
                  sheetContext.l10n.t(
                    'Choose the datum used by your survey. Its reference ellipsoid is shown below the datum name.',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView(
                  children: [
                    ListTile(
                      title: Text(ReferenceEllipsoid.wgs84.displayName),
                      subtitle: Text(
                        sheetContext.l10n.t(
                          'WGS 84 ellipsoid • Global reference system (default; valid everywhere)',
                        ),
                      ),
                      trailing:
                          currentDatum == null &&
                              currentEllipsoid == ReferenceEllipsoid.wgs84
                          ? const Icon(
                              Icons.check_circle,
                              color: Color(0xFF0C8A8C),
                            )
                          : const Icon(Icons.near_me, color: Color(0xFF0C8A8C)),
                      onTap: () async {
                        Navigator.of(sheetContext).pop();
                        await _handleEllipsoidOrDatumChange(
                          ReferenceEllipsoid.wgs84,
                          null,
                        );
                      },
                    ),
                    ...datums.map((datum) {
                      final isSelected = currentDatum?.id == datum.id;
                      final validHere =
                          currentLocation != null &&
                          datum.isValidAt(currentLocation);
                      return ListTile(
                        title: Text(sheetContext.l10n.t(datum.displayName)),
                        subtitle: Text(
                          sheetContext.l10n.t(
                                '{ellipsoid} ellipsoid • {area}\nEPSG:{code} • {accuracy} m accuracy',
                                params: {
                                  'ellipsoid':
                                      datum.parentEllipsoid.displayName,
                                  'area': sheetContext.l10n.t(datum.areaOfUse),
                                  'code': '${datum.epsgOperationCode}',
                                  'accuracy': datum.accuracyMeters
                                      .toStringAsFixed(0),
                                },
                              ) +
                              (datum.isApproximate
                                  ? sheetContext.l10n.t(' • Approximate')
                                  : '') +
                              (validHere
                                  ? sheetContext.l10n.t(' • Valid here')
                                  : ''),
                        ),
                        isThreeLine: true,
                        trailing: isSelected
                            ? const Icon(
                                Icons.check_circle,
                                color: Color(0xFF0C8A8C),
                              )
                            : validHere
                            ? const Icon(
                                Icons.near_me,
                                color: Color(0xFF0C8A8C),
                              )
                            : const Icon(Icons.circle_outlined),
                        onTap: () async {
                          Navigator.of(sheetContext).pop();
                          await _handleEllipsoidOrDatumChange(
                            datum.parentEllipsoid,
                            datum,
                          );
                        },
                      );
                    }),
                    if (datumlessEllipsoids.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                        child: Text(
                          sheetContext.l10n.t(
                            'REFERENCE / ELLIPSOID-ONLY OPTIONS',
                          ),
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      ...datumlessEllipsoids.map((ellipsoid) {
                        final isSelected =
                            currentDatum == null &&
                            currentEllipsoid == ellipsoid;
                        return ListTile(
                          title: Text(ellipsoid.displayName),
                          subtitle: Text(
                            sheetContext.l10n.t(
                              '{ellipsoid} ellipsoid • No verified datum transformation; ellipsoid-shape-only conversion',
                              params: {'ellipsoid': ellipsoid.displayName},
                            ),
                          ),
                          trailing: isSelected
                              ? const Icon(
                                  Icons.check_circle,
                                  color: Color(0xFF0C8A8C),
                                )
                              : const Icon(Icons.circle_outlined),
                          onTap: () async {
                            Navigator.of(sheetContext).pop();
                            await _handleEllipsoidOrDatumChange(
                              ellipsoid,
                              null,
                            );
                          },
                        );
                      }),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Text(
              context.l10n.t('Compass north reference'),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            ListTile(
              title: Text(context.l10n.t('Magnetic North')),
              subtitle: Text(
                context.l10n.t(
                  'Uses raw compass sensor reading. No correction applied.',
                ),
              ),
              trailing: current == CompassNorthType.magnetic
                  ? const Icon(Icons.check_circle, color: Color(0xFF0C8A8C))
                  : const Icon(Icons.circle_outlined),
              onTap: () {
                ref
                    .read(compassNorthTypeProvider.notifier)
                    .setNorthType(CompassNorthType.magnetic);
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: Text(context.l10n.t('True North')),
              subtitle: Text(
                context.l10n.t(
                  'Corrects for magnetic declination to point to geographic north.',
                ),
              ),
              trailing: current == CompassNorthType.trueNorth
                  ? const Icon(Icons.check_circle, color: Color(0xFF0C8A8C))
                  : const Icon(Icons.circle_outlined),
              onTap: () {
                ref
                    .read(compassNorthTypeProvider.notifier)
                    .setNorthType(CompassNorthType.trueNorth);
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 8),
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

  String _photoQualityLabel(PhotoCaptureQuality quality) {
    switch (quality) {
      case PhotoCaptureQuality.low:
        return 'Low';
      case PhotoCaptureQuality.medium:
        return 'Medium';
      case PhotoCaptureQuality.high:
        return 'High';
    }
  }

  String _captureModeLabel(PhotoCaptureMode mode) {
    switch (mode) {
      case PhotoCaptureMode.inApp:
        return 'Inside the app';
      case PhotoCaptureMode.systemCamera:
        return 'System camera';
    }
  }
}

class _ContactDialog extends StatefulWidget {
  const _ContactDialog();

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
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.mail_outline_rounded,
                    color: primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.t('Send feedback'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        context.l10n.t('We read every message'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.black45,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  color: Colors.black38,
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // Message field
            TextField(
              controller: _controller,
              minLines: 3,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              autofocus: true,
              decoration: InputDecoration(
                hintText: context.l10n.t(
                  'Tell us what\'s on your mind — a bug, suggestion, or question…',
                ),
                hintStyle: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 13,
                  height: 1.5,
                ),
                filled: true,
                fillColor: const Color(0xFFF5F7FA),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: primary, width: 1.8),
                ),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),

            const SizedBox(height: 16),

            // Send button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSending ? null : _send,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: _isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        context.l10n.t('Send'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
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
