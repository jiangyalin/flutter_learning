import 'package:flutter/material.dart';

import '../services/wangyi_favorites_service.dart';
import 'wangyi_playlist_songs_page.dart';

class WangYiFavoritesPage extends StatefulWidget {
  const WangYiFavoritesPage({
    super.key,
    WangYiFavoritesService? service,
  }) : service = service ??
            const WangYiFavoritesService(
              // 对齐参考项目 aaa/get-wang-yi-favorites/grab.js 里的 uid
              userId: '280316200',
            );

  final WangYiFavoritesService service;

  @override
  State<WangYiFavoritesPage> createState() => _WangYiFavoritesPageState();
}

class _WangYiFavoritesPageState extends State<WangYiFavoritesPage> {
  bool _loading = true;
  String? _error;
  List<WangYiFavoritePlaylist> _playlists = const [];

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
      final items = await widget.service.fetchFavorites();
      if (!mounted) {
        return;
      }
      setState(() {
        _playlists = items;
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
        title: const Text('网易云音乐'),
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
              ? _ErrorView(message: _error!, onRetry: _load)
              : _playlists.isEmpty
                  ? const Center(
                      child: Text(
                        '暂无歌单',
                        style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _playlists.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) => _PlaylistTile(
                        item: _playlists[index],
                        service: widget.service,
                      ),
                    ),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({
    required this.item,
    required this.service,
  });

  final WangYiFavoritePlaylist item;
  final WangYiFavoritesService service;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: ListTile(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => WangYiPlaylistSongsPage(
                playlistId: item.id,
                playlistName: item.name,
                service: service,
              ),
            ),
          );
        },
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFFEE2E2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: item.coverUrl.isEmpty
              ? const Icon(Icons.queue_music_rounded, color: Color(0xFFEF4444))
              : ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    item.coverUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.queue_music_rounded,
                      color: Color(0xFFEF4444),
                    ),
                  ),
                ),
        ),
        title: Text(
          item.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF111827),
          ),
        ),
        subtitle: Text(
          '${item.trackCount} 首'
          '${item.creatorName == null || item.creatorName!.isEmpty ? '' : ' · ${item.creatorName}'}',
          style: const TextStyle(color: Color(0xFF6B7280)),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 48, color: Color(0xFFDC2626)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFB42318),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
