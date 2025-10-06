import 'package:freezed_annotation/freezed_annotation.dart';

part 'track.freezed.dart';
part 'track.g.dart';

/// Track domain model (immutable) using Freezed.
/// Run code generation: `dart run build_runner build --delete-conflicting-outputs`
@freezed
class Track with _$Track {
  const Track._();
  const factory Track({
    required String id,
    required String title,
    required String artistName,
    /// Duration in milliseconds (store as primitive for JSON friendliness)
    required int durationMs,
    String? albumId,
    String? previewUrl,
    String? coverUrl,
  }) = _Track;

  factory Track.fromJson(Map<String, dynamic> json) => _$TrackFromJson(json);

  Duration get duration => Duration(milliseconds: durationMs);
}
