import 'package:latlong2/latlong.dart';

class LandMapState {
  final LatLng? current;
  final double? accuracyMeters;
  final List<LatLng> points;
  final bool isSaving;

  const LandMapState({
    required this.current,
    required this.accuracyMeters,
    required this.points,
    required this.isSaving,
  });

  factory LandMapState.initial() => const LandMapState(
    current: null,
    accuracyMeters: null,
    points: [],
    isSaving: false,
  );

  LandMapState copyWith({
    LatLng? current,
    double? accuracyMeters,
    List<LatLng>? points,
    bool? isSaving,
  }) {
    return LandMapState(
      current: current ?? this.current,
      accuracyMeters: accuracyMeters ?? this.accuracyMeters,
      points: points ?? this.points,
      isSaving: isSaving ?? this.isSaving,
    );
  }
}
