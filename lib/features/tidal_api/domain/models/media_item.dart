class MediaTrack {
  final String id;
  final String title;
  final String artistName;
  final String albumTitle;
  final String coverUrl;
  final int durationSeconds;

  MediaTrack({
    required this.id,
    required this.title,
    required this.artistName,
    required this.albumTitle,
    required this.coverUrl,
    required this.durationSeconds,
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

    final coverPath = (coverUuid.isNotEmpty && coverUuid.contains('-'))
        ? 'https://resources.tidal.com/images/${coverUuid.replaceAll("-", "/")}/640x640.jpg'
        : (coverUuid.startsWith('http'))
            ? coverUuid
            : '';

    final duration = (json['duration'] as num?)?.toInt() ?? 0;

    return MediaTrack(
      id: id,
      title: title,
      artistName: artist,
      albumTitle: album,
      coverUrl: coverPath,
      durationSeconds: duration,
    );
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
    final coverPath = (coverUuid.isNotEmpty && coverUuid.contains('-'))
        ? 'https://resources.tidal.com/images/${coverUuid.replaceAll("-", "/")}/640x640.jpg'
        : (coverUuid.startsWith('http'))
            ? coverUuid
            : '';

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
    final coverPath = (imageUuid.isNotEmpty && imageUuid.contains('-'))
        ? 'https://resources.tidal.com/images/${imageUuid.replaceAll("-", "/")}/640x640.jpg'
        : (imageUuid.startsWith('http'))
            ? imageUuid
            : '';

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
    final picPath = (picUuid.isNotEmpty && picUuid.contains('-'))
        ? 'https://resources.tidal.com/images/${picUuid.replaceAll("-", "/")}/320x320.jpg'
        : (picUuid.startsWith('http'))
            ? picUuid
            : '';
    return MediaArtist(
      id: json['id'].toString(),
      name: json['name'] as String? ?? '',
      pictureUrl: picPath,
    );
  }
}
