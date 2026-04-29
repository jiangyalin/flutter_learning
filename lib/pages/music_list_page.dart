import 'package:flutter/material.dart';

class MusicListPage extends StatelessWidget {
  const MusicListPage({super.key});

  @override
  Widget build(BuildContext context) {
    const platforms = <_MusicPlatform>[
      _MusicPlatform(
        name: '网易云音乐',
        subtitle: '同步歌单、收藏与每日推荐',
        icon: Icons.music_note_rounded,
        color: Color(0xFFEF4444),
      ),
      _MusicPlatform(
        name: '酷狗音乐',
        subtitle: '查看本地与在线歌曲列表',
        icon: Icons.graphic_eq_rounded,
        color: Color(0xFF2563EB),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('音乐列表')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: platforms.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final platform = platforms[index];
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: ListTile(
              onTap: () {},
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: platform.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(platform.icon, color: platform.color),
              ),
              title: Text(
                platform.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                ),
              ),
              subtitle: Text(
                platform.subtitle,
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 13,
                ),
              ),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF94A3B8),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MusicPlatform {
  const _MusicPlatform({
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String name;
  final String subtitle;
  final IconData icon;
  final Color color;
}
