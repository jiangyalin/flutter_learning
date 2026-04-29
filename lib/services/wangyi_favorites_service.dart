import 'dart:convert';

import 'package:http/http.dart' as http;

class WangYiFavoritePlaylist {
  const WangYiFavoritePlaylist({
    required this.id,
    required this.name,
    required this.coverUrl,
    required this.trackCount,
    required this.category,
    this.creatorName,
  });

  final String id;
  final String name;
  final String coverUrl;
  final int trackCount;
  final String category;
  final String? creatorName;
}

class WangYiPlaylistSong {
  const WangYiPlaylistSong({
    required this.id,
    required this.name,
    this.artist,
    this.album,
  });

  final String id;
  final String name;
  final String? artist;
  final String? album;
}

class WangYiFavoritesService {
  const WangYiFavoritesService({
    required this.userId,
    this.pageSize = 300,
  });

  final String userId;
  final int pageSize;

  Future<List<WangYiFavoritePlaylist>> fetchFavorites() async {
    // 对齐参考项目 get-wang-yi-favorites/grab.js:
    // POST https://music.163.com/api/user/playlist?uid=...&limit=300&offset=0&includeVideo=true
    final uri = Uri.https('music.163.com', '/api/user/playlist', {
      'uid': userId,
      'limit': '$pageSize',
      'offset': '0',
      'includeVideo': 'true',
    });
    final response = await http.post(
      uri,
      headers: {
        'accept': 'application/json, text/plain, */*',
        'referer': 'https://music.163.com/user?id=$userId',
        'origin': 'https://music.163.com',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('请求失败: ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    final items = _extractPlaylistItems(decoded);
    final mine = items.where((item) {
      final creator = item['creator'];
      final creatorId = creator is Map<String, dynamic>
          ? creator['userId']?.toString()
          : null;
      return creatorId == userId;
    }).toList(growable: false);
    return mine.map(_toPlaylist).toList(growable: false);
  }

  Future<List<WangYiPlaylistSong>> fetchPlaylistSongs({
    required String playlistId,
  }) async {
    final uri = Uri.https('music.163.com', '/api/v6/playlist/detail', {
      'id': playlistId,
      'limit': '$pageSize',
    });
    final response = await http.post(
      uri,
      headers: {
        'accept': 'application/json, text/plain, */*',
        'referer': 'https://music.163.com/playlist?id=$playlistId',
        'origin': 'https://music.163.com',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('请求失败: ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return const [];
    }
    final playlist = decoded['playlist'];
    if (playlist is! Map<String, dynamic>) {
      return const [];
    }

    final trackIds = _extractTrackIds(playlist);
    if (trackIds.isNotEmpty) {
      final songs = await _fetchSongsByTrackIds(
        trackIds: trackIds,
        playlistId: playlistId,
      );
      if (songs.isNotEmpty) {
        return songs;
      }
    }

    final tracks = playlist['tracks'];
    if (tracks is! List) {
      return const [];
    }
    return tracks
        .whereType<Map<String, dynamic>>()
        .map(_toSong)
        .toList(growable: false);
  }

  List<String> _extractTrackIds(Map<String, dynamic> playlist) {
    final trackIdsRaw = playlist['trackIds'];
    if (trackIdsRaw is! List) {
      return const [];
    }
    return trackIdsRaw
        .whereType<Map<String, dynamic>>()
        .map((item) => item['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<WangYiPlaylistSong>> _fetchSongsByTrackIds({
    required List<String> trackIds,
    required String playlistId,
  }) async {
    const chunkSize = 100;
    final all = <WangYiPlaylistSong>[];
    for (var start = 0; start < trackIds.length; start += chunkSize) {
      final end = (start + chunkSize > trackIds.length)
          ? trackIds.length
          : start + chunkSize;
      final chunk = trackIds.sublist(start, end);

      final c = jsonEncode(
        chunk.map((id) => {'id': int.tryParse(id) ?? id}).toList(),
      );
      final uri = Uri.https('music.163.com', '/api/v3/song/detail');
      final response = await http.post(
        uri,
        headers: {
          'accept': 'application/json, text/plain, */*',
          'referer': 'https://music.163.com/playlist?id=$playlistId',
          'origin': 'https://music.163.com',
          'content-type': 'application/x-www-form-urlencoded; charset=UTF-8',
        },
        body: {'c': c},
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        continue;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        continue;
      }
      final songs = decoded['songs'];
      if (songs is! List) {
        continue;
      }
      final songMap = <String, WangYiPlaylistSong>{};
      for (final song in songs.whereType<Map<String, dynamic>>()) {
        final mapped = _toSong(song);
        if (mapped.id.isNotEmpty) {
          songMap[mapped.id] = mapped;
        }
      }
      for (final id in chunk) {
        final song = songMap[id];
        if (song != null) {
          all.add(song);
        }
      }
    }
    return all;
  }

  WangYiPlaylistSong _toSong(Map<String, dynamic> track) {
    final artists = track['ar'] is List
        ? (track['ar'] as List).whereType<Map<String, dynamic>>().toList()
        : const <Map<String, dynamic>>[];
    final artist = artists.isEmpty
        ? null
        : artists
            .map((e) => e['name']?.toString() ?? '')
            .where((e) => e.isNotEmpty)
            .join(' / ');
    final album = track['al'] is Map<String, dynamic>
        ? (track['al'] as Map<String, dynamic>)['name']?.toString()
        : null;
    return WangYiPlaylistSong(
      id: track['id']?.toString() ?? '',
      name: track['name']?.toString() ?? '未命名歌曲',
      artist: artist,
      album: album,
    );
  }

  List<Map<String, dynamic>> _extractPlaylistItems(dynamic decoded) {
    if (decoded is List) {
      return decoded.whereType<Map<String, dynamic>>().toList();
    }
    if (decoded is! Map<String, dynamic>) {
      return const [];
    }

    final candidates = [
      decoded['playlists'],
      decoded['playlist'],
      decoded['data'],
      decoded['list'],
      if (decoded['data'] is Map<String, dynamic>)
        (decoded['data'] as Map<String, dynamic>)['playlists'],
      if (decoded['data'] is Map<String, dynamic>)
        (decoded['data'] as Map<String, dynamic>)['list'],
    ];

    for (final candidate in candidates) {
      if (candidate is List) {
        return candidate.whereType<Map<String, dynamic>>().toList();
      }
    }
    return const [];
  }

  WangYiFavoritePlaylist _toPlaylist(Map<String, dynamic> item) {
    final tags = item['tags'] is List
        ? (item['tags'] as List).whereType<String>().toList()
        : const <String>[];
    final creator = item['creator'] is Map<String, dynamic>
        ? item['creator'] as Map<String, dynamic>
        : const <String, dynamic>{};

    final playlistName = item['name']?.toString() ?? '未命名歌单';
    final category = tags.isNotEmpty ? tags.first : '未分类';

    return WangYiFavoritePlaylist(
      id: item['id']?.toString() ?? '',
      name: playlistName,
      coverUrl: item['coverImgUrl']?.toString() ?? '',
      trackCount:
          item['trackCount'] is num ? (item['trackCount'] as num).toInt() : 0,
      category: category,
      creatorName: creator['nickname']?.toString(),
    );
  }
}
