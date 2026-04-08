import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../models/coordinate_format.dart';
import '../models/reference_ellipsoid.dart';

enum DistanceUnit { meters, feet }

enum PhotoCaptureQuality { low, medium, high }

enum PhotoCaptureMode { inApp, systemCamera }

final coordinateFormatProvider =
    NotifierProvider<CoordinateFormatNotifier, CoordinateFormat>(
      CoordinateFormatNotifier.new,
    );

final distanceUnitProvider =
    NotifierProvider<DistanceUnitNotifier, DistanceUnit>(
      DistanceUnitNotifier.new,
    );

final saveOriginalPhotoProvider =
    NotifierProvider<SaveOriginalPhotoNotifier, bool>(
      SaveOriginalPhotoNotifier.new,
    );

final saveToGalleryProvider = NotifierProvider<SaveToGalleryNotifier, bool>(
  SaveToGalleryNotifier.new,
);

final photoQualityProvider =
    NotifierProvider<PhotoQualityNotifier, PhotoCaptureQuality>(
      PhotoQualityNotifier.new,
    );

final photoCaptureModeProvider =
    NotifierProvider<PhotoCaptureModeNotifier, PhotoCaptureMode>(
      PhotoCaptureModeNotifier.new,
    );

final referenceEllipsoidProvider =
    NotifierProvider<ReferenceEllipsoidNotifier, ReferenceEllipsoid>(
      ReferenceEllipsoidNotifier.new,
    );

const _saveOriginalPhotoKey = 'prefs_photo_save_original';
const _saveToGalleryKey = 'prefs_photo_save_to_gallery';
const _photoQualityKey = 'prefs_photo_quality';
const _photoCaptureModeKey = 'prefs_photo_capture_mode';
const _referenceEllipsoidKey = 'prefs_reference_ellipsoid';

class CoordinateFormatNotifier extends Notifier<CoordinateFormat> {
  @override
  CoordinateFormat build() {
    return CoordinateFormat.decimalDegrees;
  }

  void setFormat(CoordinateFormat format) {
    state = format;
  }
}

class DistanceUnitNotifier extends Notifier<DistanceUnit> {
  @override
  DistanceUnit build() {
    return DistanceUnit.feet;
  }

  void setUnit(DistanceUnit unit) {
    state = unit;
  }
}

class SaveOriginalPhotoNotifier extends Notifier<bool> {
  @override
  bool build() {
    final box = Hive.box('landbox');
    final saved = box.get(_saveOriginalPhotoKey);
    if (saved is bool) return saved;
    return true;
  }

  Future<void> setValue(bool value) async {
    state = value;
    final box = Hive.box('landbox');
    await box.put(_saveOriginalPhotoKey, value);
  }
}

class SaveToGalleryNotifier extends Notifier<bool> {
  @override
  bool build() {
    final box = Hive.box('landbox');
    final saved = box.get(_saveToGalleryKey);
    if (saved is bool) return saved;
    return true;
  }

  Future<void> setValue(bool value) async {
    state = value;
    final box = Hive.box('landbox');
    await box.put(_saveToGalleryKey, value);
  }
}

class PhotoQualityNotifier extends Notifier<PhotoCaptureQuality> {
  @override
  PhotoCaptureQuality build() {
    final box = Hive.box('landbox');
    final raw = box.get(_photoQualityKey)?.toString();
    return _qualityFromRaw(raw);
  }

  Future<void> setQuality(PhotoCaptureQuality quality) async {
    state = quality;
    final box = Hive.box('landbox');
    await box.put(_photoQualityKey, quality.name);
  }

  PhotoCaptureQuality _qualityFromRaw(String? raw) {
    for (final q in PhotoCaptureQuality.values) {
      if (q.name == raw) return q;
    }
    return PhotoCaptureQuality.high;
  }
}

class PhotoCaptureModeNotifier extends Notifier<PhotoCaptureMode> {
  @override
  PhotoCaptureMode build() {
    final box = Hive.box('landbox');
    final raw = box.get(_photoCaptureModeKey)?.toString();
    return _modeFromRaw(raw);
  }

  Future<void> setMode(PhotoCaptureMode mode) async {
    state = mode;
    final box = Hive.box('landbox');
    await box.put(_photoCaptureModeKey, mode.name);
  }

  PhotoCaptureMode _modeFromRaw(String? raw) {
    for (final m in PhotoCaptureMode.values) {
      if (m.name == raw) return m;
    }
    return PhotoCaptureMode.inApp;
  }
}

class ReferenceEllipsoidNotifier extends Notifier<ReferenceEllipsoid> {
  @override
  ReferenceEllipsoid build() {
    final box = Hive.box('landbox');
    final raw = box.get(_referenceEllipsoidKey)?.toString();
    return ReferenceEllipsoid.fromRaw(raw);
  }

  Future<void> setEllipsoid(ReferenceEllipsoid ellipsoid) async {
    state = ellipsoid;
    final box = Hive.box('landbox');
    await box.put(_referenceEllipsoidKey, ellipsoid.name);
  }
}
