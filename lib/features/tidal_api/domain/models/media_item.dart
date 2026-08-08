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

  factory MediaTrack.fromJson(Map<String, dynamic> json) {
    final coverUuid = json['album']?['cover'] as String? ?? '';
    final coverPath = coverUuid.isNotEmpty
        ? 'https://resources.tidal.com/images/${coverUuid.replaceAll("-", "/")}/640x640.jpg'
        : '';
    return MediaTrack(
      id: json['id'].toString(),
      title: json['title'] as String? ?? '',
      artistName: json['artist']?['name'] as String? ?? '',
      albumTitle: json['album']?['title'] as String? ?? '',
      coverUrl: coverPath,
      durationSeconds: json['duration'] as int? ?? 0,
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

  factory MediaAlbum.fromJson(Map<String, dynamic> json) {
    final coverUuid = json['cover'] as String? ?? '';
    final coverPath = coverUuid.isNotEmpty
        ? 'https://resources.tidal.com/images/${coverUuid.replaceAll("-", "/")}/640x640.jpg'
        : '';
    return MediaAlbum(
      id: json['id'].toString(),
      title: json['title'] as String? ?? '',
      artistName: json['artist']?['name'] as String? ?? '',
      coverUrl: coverPath,
      numberOfTracks: json['numberOfTracks'] as int? ?? 0,
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

  factory MediaPlaylist.fromJson(Map<String, dynamic> json) {
    final squareUuid = json['squareImage'] as String? ?? json['uuid'] as String? ?? '';
    final coverPath = squareUuid.isNotEmpty
        ? 'https://resources.tidal.com/images/${squareUuid.replaceAll("-", "/")}/640x640.jpg'
        : '';
    return MediaPlaylist(
      id: json['uuid'] as String? ?? json['id']?.toString() ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      coverUrl: coverPath,
      numberOfTracks: json['numberOfTracks'] as int? ?? 0,
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
    final picPath = picUuid.isNotEmpty
        ? 'https://resources.tidal.com/images/${picUuid.replaceAll("-", "/")}/320x320.jpg'
        : '';
    return MediaArtist(
      id: json['id'].toString(),
      name: json['name'] as String? ?? '',
      pictureUrl: picPath,
    );
  }
}
