import 'package:flutter/material.dart';

import '../services/wangyi_favorites_service.dart';

class WangYiPlaylistSongsPage extends StatefulWidget {
  const WangYiPlaylistSongsPage({
    super.key,
    required this.playlistId,
    required this.playlistName,
    required this.service,
  });

  final String playlistId;
  final String playlistName;
  final WangYiFavoritesService service;

  @override
  State<WangYiPlaylistSongsPage> createState() =>
      _WangYiPlaylistSongsPageState();
}

class _WangYiPlaylistSongsPageState extends State<WangYiPlaylistSongsPage> {
  bool _loading = true;
  String? _error;
  List<WangYiPlaylistSong> _songs = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final songs = await widget.service
          .fetchPlaylistSongs(playlistId: widget.playlistId);
      if (!mounted) {
        return;
      }
      setState(() {
        _songs = songs;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.playlistName),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFB42318),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
              : _songs.isEmpty
                  ? const Center(
                      child: Text(
                        '歌单暂无歌曲',
                        style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _songs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final song = _songs[index];
                        final subtitle = [
                          if (song.artist != null && song.artist!.isNotEmpty)
                            song.artist!,
                          if (song.album != null && song.album!.isNotEmpty)
                            song.album!,
                        ].join(' · ');
                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFFEEF2FF)
                                  .withValues(alpha: 0.9),
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  color: Color(0xFF4F46E5),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            title: Text(
                              song.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF111827),
                              ),
                            ),
                            subtitle: subtitle.isEmpty
                                ? null
                                : Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Color(0xFF6B7280)),
                                  ),
                          ),
                        );
                      },
                    ),
    );
  }
}
