// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'track.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$TrackImpl _$$TrackImplFromJson(Map<String, dynamic> json) => _$TrackImpl(
      id: json['id'] as String,
      title: json['title'] as String,
      artistName: json['artistName'] as String,
      durationMs: (json['durationMs'] as num).toInt(),
      albumId: json['albumId'] as String?,
      previewUrl: json['previewUrl'] as String?,
      coverUrl: json['coverUrl'] as String?,
      views: (json['views'] as num?)?.toInt(),
    );

Map<String, dynamic> _$$TrackImplToJson(_$TrackImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'artistName': instance.artistName,
      'durationMs': instance.durationMs,
      'albumId': instance.albumId,
      'previewUrl': instance.previewUrl,
      'coverUrl': instance.coverUrl,
      'views': instance.views,
    };
