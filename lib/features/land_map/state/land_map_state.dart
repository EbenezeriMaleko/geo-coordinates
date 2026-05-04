import 'package:latlong2/latlong.dart';

class LandNavigationTarget {
  final LatLng point;
  final String label;
  final String kind;

  const LandNavigationTarget({
    required this.point,
    required this.label,
    required this.kind,
  });
}

class LandMapState {
  final LatLng? current;
  final double? accuracyMeters;
  final double? altitudeMeters;
  final DateTime? locationTimestamp;
  final List<LatLng> points;
  final bool isSaving;
  final String? activeFieldId;
  final String? activeFieldName;
  final LandNavigationTarget? navigationTarget;

  const LandMapState({
    required this.current,
    required this.accuracyMeters,
    required this.altitudeMeters,
    required this.locationTimestamp,
    required this.points,
    required this.isSaving,
    required this.activeFieldId,
    required this.activeFieldName,
    required this.navigationTarget,
  });

  factory LandMapState.initial() => const LandMapState(
    current: null,
    accuracyMeters: null,
    altitudeMeters: null,
    locationTimestamp: null,
    points: [],
    isSaving: false,
    activeFieldId: null,
    activeFieldName: null,
    navigationTarget: null,
  );

  LandMapState copyWith({
    LatLng? current,
    double? accuracyMeters,
    double? altitudeMeters,
    DateTime? locationTimestamp,
    List<LatLng>? points,
    bool? isSaving,
    String? activeFieldId,
    String? activeFieldName,
    LandNavigationTarget? navigationTarget,
    bool clearActiveField = false,
    bool clearNavigationTarget = false,
  }) {
    return LandMapState(
      current: current ?? this.current,
      accuracyMeters: accuracyMeters ?? this.accuracyMeters,
      altitudeMeters: altitudeMeters ?? this.altitudeMeters,
      locationTimestamp: locationTimestamp ?? this.locationTimestamp,
      points: points ?? this.points,
      isSaving: isSaving ?? this.isSaving,
      activeFieldId: clearActiveField
          ? null
          : (activeFieldId ?? this.activeFieldId),
      activeFieldName: clearActiveField
          ? null
          : (activeFieldName ?? this.activeFieldName),
      navigationTarget: clearNavigationTarget
          ? null
          : (navigationTarget ?? this.navigationTarget),
    );
  }
}
