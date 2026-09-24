/// Data models for the subset of the Immich API this app uses.

class Album {
  final String id;
  final String name;
  final int assetCount;
  final String? thumbnailAssetId;
  final DateTime? updatedAt;

  const Album({
    required this.id,
    required this.name,
    required this.assetCount,
    this.thumbnailAssetId,
    this.updatedAt,
  });

  factory Album.fromJson(Map<String, dynamic> j) {
    return Album(
      id: j['id'] as String,
      name: (j['albumName'] as String?)?.trim().isNotEmpty == true
          ? j['albumName'] as String
          : 'Untitled Album',
      assetCount: (j['assetCount'] as num?)?.toInt() ?? 0,
      thumbnailAssetId: j['albumThumbnailAssetId'] as String?,
      updatedAt: DateTime.tryParse(j['updatedAt']?.toString() ?? ''),
    );
  }
}

enum AssetType { image, video, other }

class Asset {
  final String id;
  final AssetType type;
  final String? fileName;
  final Duration? duration;

  /// When the photo was taken, as the camera's clock read it.
  ///
  /// From Immich's `localDateTime`, which is wall-clock time written with a
  /// trailing "Z" even though it is not UTC. Kept as parsed — read its year
  /// and month directly, never `.toLocal()` it, or a photo taken late on the
  /// last day of a month moves into the next one.
  final DateTime? taken;

  const Asset({
    required this.id,
    required this.type,
    this.fileName,
    this.duration,
    this.taken,
  });

  bool get isImage => type == AssetType.image;
  bool get isVideo => type == AssetType.video;

  factory Asset.fromJson(Map<String, dynamic> j) {
    final t = (j['type'] ?? '').toString().toUpperCase();
    return Asset(
      id: j['id'] as String,
      type: t == 'VIDEO'
          ? AssetType.video
          : (t == 'IMAGE' ? AssetType.image : AssetType.other),
      fileName: j['originalFileName'] as String?,
      duration: _parseDuration(j['duration']?.toString()),
      taken: DateTime.tryParse(
          (j['localDateTime'] ?? j['fileCreatedAt'] ?? '').toString()),
    );
  }
}

/// Immich sends durations like "0:00:16.96000" (H:MM:SS.frac).
Duration? _parseDuration(String? s) {
  if (s == null || s.isEmpty) return null;
  try {
    final parts = s.split(':');
    if (parts.length != 3) return null;
    final h = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final sec = double.parse(parts[2]);
    return Duration(
      hours: h,
      minutes: m,
      milliseconds: (sec * 1000).round(),
    );
  } catch (_) {
    return null;
  }
}
