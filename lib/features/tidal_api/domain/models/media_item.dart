/// TIDAL 이미지 UUID(예: 1a2b-3c4d-...)를 이미지 주소로 바꾼다. 이미 주소면 그대로, 비어 있으면 빈 문자열.
String tidalImageUrl(String uuidOrUrl, {int size = 640}) {
  if (uuidOrUrl.startsWith('http')) return uuidOrUrl;
  if (uuidOrUrl.isEmpty || !uuidOrUrl.contains('-')) return '';
  return 'https://resources.tidal.com/images/${uuidOrUrl.replaceAll('-', '/')}/${size}x$size.jpg';
}

class MediaTrack {
  final String id;
  final String title;
  final String artistName;
  final String albumTitle;
  final String coverUrl;
  final int durationSeconds;
  final String audioQuality;

  MediaTrack({
    required this.id,
    required this.title,
    required this.artistName,
    required this.albumTitle,
    required this.coverUrl,
    required this.durationSeconds,
    this.audioQuality = 'LOSSLESS',
  });

  factory MediaTrack.fromJson(Map<String, dynamic> rawJson) {
    final json = (rawJson['item'] is Map<String, dynamic>)
        ? rawJson['item'] as Map<String, dynamic>
        : (rawJson['track'] is Map<String, dynamic>)
            ? rawJson['track'] as Map<String, dynamic>
            : rawJson;

    final id = json['id']?.toString() ?? '';
    final title = json['title'] as String? ?? json['name'] as String? ?? '';
    
    // Artist name parsing
    String artist = '';
    if (json['artist'] is Map && json['artist']['name'] != null) {
      artist = json['artist']['name'].toString();
    } else if (json['artists'] is List && (json['artists'] as List).isNotEmpty) {
      final firstArtist = (json['artists'] as List).first;
      if (firstArtist is Map && firstArtist['name'] != null) {
        artist = firstArtist['name'].toString();
      }
    } else if (json['artistName'] != null) {
      artist = json['artistName'].toString();
    }

    // Album title parsing
    String album = '';
    if (json['album'] is Map && json['album']['title'] != null) {
      album = json['album']['title'].toString();
    } else if (json['albumTitle'] != null) {
      album = json['albumTitle'].toString();
    }

    // Cover image UUID parsing
    String coverUuid = '';
    if (json['album'] is Map && json['album']['cover'] != null) {
      coverUuid = json['album']['cover'].toString();
    } else if (json['cover'] != null) {
      coverUuid = json['cover'].toString();
    }

    final coverPath = tidalImageUrl(coverUuid);

    final duration = (json['duration'] as num?)?.toInt() ?? 0;
    
    // Quality tag resolution (TIDAL API는 Hi-Res 24-bit 음원이어도 기본 audioQuality 필드에는 LOSSLESS로 오므로 tags 및 audioModes 우선 분석)
    String quality = '';
    
    // 1. mediaMetadata.tags 분석 (가장 신뢰성 높음: HIRES_LOSSLESS, LOSSLESS, DOLBY_ATMOS)
    if (json['mediaMetadata'] is Map && json['mediaMetadata']['tags'] is List) {
      final tags = (json['mediaMetadata']['tags'] as List).map((e) => e.toString().toUpperCase()).toList();
      if (tags.any((t) => t.contains('HIRES') || t.contains('HI_RES') || t.contains('MQA'))) {
        quality = 'HI_RES_LOSSLESS';
      } else if (tags.any((t) => t.contains('DOLBY') || t.contains('ATMOS'))) {
        quality = 'DOLBY_ATMOS';
      } else if (tags.contains('LOSSLESS')) {
        quality = 'LOSSLESS';
      }
    }

    // 2. audioModes 분석 (예: ["STEREO", "HIRES_LOSSLESS"])
    if (quality.isEmpty && json['audioModes'] != null) {
      final modesStr = json['audioModes'].toString().toUpperCase();
      if (modesStr.contains('HIRES') || modesStr.contains('HI_RES')) {
        quality = 'HI_RES_LOSSLESS';
      } else if (modesStr.contains('DOLBY') || modesStr.contains('ATMOS')) {
        quality = 'DOLBY_ATMOS';
      }
    }

    // 3. audioQuality 필드 분석 (LOSSLESS, HIGH, LOW)
    if (quality.isEmpty) {
      final aq = (json['audioQuality'] ?? '').toString().toUpperCase();
      if (aq.contains('HI_RES') || aq.contains('HIRES') || aq.contains('MAX')) {
        quality = 'HI_RES_LOSSLESS';
      } else if (aq.contains('LOSSLESS') || aq.contains('FLAC')) {
        quality = 'LOSSLESS';
      } else if (aq.contains('HIGH')) {
        quality = 'HIGH';
      } else if (aq.contains('LOW')) {
        quality = 'LOW';
      } else {
        quality = 'LOSSLESS';
      }
    }

    return MediaTrack(
      id: id,
      title: title,
      artistName: artist,
      albumTitle: album,
      coverUrl: coverPath,
      durationSeconds: duration,
      audioQuality: quality,
    );
  }

  bool get isMax => audioQuality.toUpperCase().contains('HI_RES') || audioQuality.toUpperCase().contains('HIRES') || audioQuality.toUpperCase().contains('MAX') || audioQuality.toUpperCase().contains('MQA');
  bool get isAtmos => audioQuality.toUpperCase().contains('DOLBY') || audioQuality.toUpperCase().contains('ATMOS');
  bool get isLossless => isMax || isAtmos || audioQuality.toUpperCase().contains('LOSSLESS') || audioQuality.toUpperCase().contains('FLAC');
  
  String get qualityBadgeText {
    if (isMax) return 'MAX';
    if (isAtmos) return 'ATMOS';
    if (isLossless) return 'FLAC';
    if (audioQuality.toUpperCase().contains('HIGH')) return 'HIGH';
    return 'LOW';
  }
}

class MediaAlbum {
  final String id;
  final String title;
  final String artistName;
  final String coverUrl;
  final int numberOfTracks;

  MediaAlbum({
    required this.id,
    required this.title,
    required this.artistName,
    required this.coverUrl,
    required this.numberOfTracks,
  });

  factory MediaAlbum.fromJson(Map<String, dynamic> rawJson) {
    final json = (rawJson['item'] is Map<String, dynamic>)
        ? rawJson['item'] as Map<String, dynamic>
        : (rawJson['album'] is Map<String, dynamic>)
            ? rawJson['album'] as Map<String, dynamic>
            : rawJson;

    final id = json['id']?.toString() ?? '';
    final title = json['title'] as String? ?? json['name'] as String? ?? '';
    
    String artist = '';
    if (json['artist'] is Map && json['artist']['name'] != null) {
      artist = json['artist']['name'].toString();
    } else if (json['artists'] is List && (json['artists'] as List).isNotEmpty) {
      final firstArtist = (json['artists'] as List).first;
      if (firstArtist is Map && firstArtist['name'] != null) {
        artist = firstArtist['name'].toString();
      }
    } else if (json['artistName'] != null) {
      artist = json['artistName'].toString();
    }

    final coverUuid = json['cover']?.toString() ?? '';
    final coverPath = tidalImageUrl(coverUuid);

    final numberOfTracks = (json['numberOfTracks'] as num?)?.toInt() ??
        (json['trackCount'] as num?)?.toInt() ??
        (json['itemsCount'] as num?)?.toInt() ??
        0;

    return MediaAlbum(
      id: id,
      title: title,
      artistName: artist,
      coverUrl: coverPath,
      numberOfTracks: numberOfTracks,
    );
  }
}

class MediaPlaylist {
  final String id;
  final String title;
  final String description;
  final String coverUrl;
  final int numberOfTracks;

  MediaPlaylist({
    required this.id,
    required this.title,
    required this.description,
    required this.coverUrl,
    required this.numberOfTracks,
  });

  factory MediaPlaylist.fromJson(Map<String, dynamic> rawJson) {
    final json = (rawJson['playlist'] is Map<String, dynamic>)
        ? rawJson['playlist'] as Map<String, dynamic>
        : (rawJson['item'] is Map<String, dynamic>)
            ? rawJson['item'] as Map<String, dynamic>
            : rawJson;

    final id = json['uuid'] as String? ?? json['id']?.toString() ?? '';
    final title = json['title'] as String? ?? json['name'] as String? ?? '';
    final description = json['description'] as String? ?? '';

    // Extract image UUID (squareImage or image, not uuid)
    final imageUuid = json['squareImage'] as String? ?? json['image'] as String? ?? '';
    final coverPath = tidalImageUrl(imageUuid);

    final numberOfTracks = (json['numberOfTracks'] as num?)?.toInt() ??
        (json['trackCount'] as num?)?.toInt() ??
        (json['itemsCount'] as num?)?.toInt() ??
        0;

    return MediaPlaylist(
      id: id,
      title: title,
      description: description,
      coverUrl: coverPath,
      numberOfTracks: numberOfTracks,
    );
  }
}

class MediaArtist {
  final String id;
  final String name;
  final String pictureUrl;

  MediaArtist({
    required this.id,
    required this.name,
    required this.pictureUrl,
  });

  factory MediaArtist.fromJson(Map<String, dynamic> json) {
    final picUuid = json['picture'] as String? ?? '';
    final picPath = tidalImageUrl(picUuid, size: 320);
    return MediaArtist(
      id: json['id'].toString(),
      name: json['name'] as String? ?? '',
      pictureUrl: picPath,
    );
  }
}
