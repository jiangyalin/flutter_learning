import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final tools = <_ToolItem>[
      const _ToolItem('待办清单', Icons.fact_check_outlined, Color(0xFF2563EB)),
      const _ToolItem('灵感便签', Icons.lightbulb_outline_rounded, Color(0xFFF59E0B)),
      const _ToolItem('番茄计时', Icons.timer_outlined, Color(0xFFEF4444)),
      const _ToolItem('日程提醒', Icons.notifications_active_outlined, Color(0xFF7C3AED)),
      const _ToolItem('AI 小助手', Icons.auto_awesome_rounded, Color(0xFF8B5CF6)),
      const _ToolItem('拍照扫描', Icons.document_scanner_rounded, Color(0xFF0EA5E9)),
      const _ToolItem('截图收集', Icons.photo_library_outlined, Color(0xFF10B981)),
      const _ToolItem('书签中转站', Icons.bookmarks_outlined, Color(0xFF3B82F6)),
      const _ToolItem('记账角落', Icons.account_balance_wallet_outlined, Color(0xFF14B8A6)),
      const _ToolItem('体重记录', Icons.monitor_weight_outlined, Color(0xFFE11D48)),
      const _ToolItem('喝水提醒', Icons.water_drop_outlined, Color(0xFF0891B2)),
      const _ToolItem('文件快传', Icons.swap_horizontal_circle_outlined, Color(0xFF4F46E5)),
      const _ToolItem('素材仓库', Icons.inventory_2_outlined, Color(0xFF9333EA)),
      const _ToolItem('设备遥控', Icons.router_rounded, Color(0xFF059669)),
      const _ToolItem('习惯追踪', Icons.favorite_rounded, Color(0xFFF97316)),
      const _ToolItem('实验开关', Icons.science_outlined, Color(0xFFEA580C)),
    ];

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF9FBFF), Color(0xFFF2F5FB)],
          ),
        ),
        child: Stack(
          children: [
            const Positioned(
              top: -80,
              right: -40,
              child: _BlurOrb(
                size: 220,
                color: Color(0x220E5BFF),
              ),
            ),
            const Positioned(
              top: 120,
              left: -70,
              child: _BlurOrb(
                size: 180,
                color: Color(0x18F97316),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 14),
                    const Text(
                      '我的实验应用',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF111827),
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '所有功能入口都平铺在这里',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF667085),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.only(bottom: 8),
                        itemCount: tools.length,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.95,
                        ),
                        itemBuilder: (context, index) {
                          return _ToolCard(
                            tool: tools[index],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.tool,
  });

  final _ToolItem tool;

  @override
  Widget build(BuildContext context) {
    final accent = tool.color;
    final highlightColor = Color.lerp(accent, Colors.white, 0.82)!;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, highlightColor],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.10),
            blurRadius: 22,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        accent.withValues(alpha: 0.22),
                        accent.withValues(alpha: 0.10),
                      ],
                    ),
                  ),
                  child: Icon(tool.icon, color: accent, size: 30),
                ),
                const SizedBox(height: 16),
                Text(
                  tool.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolItem {
  const _ToolItem(this.title, this.icon, this.color);

  final String title;
  final IconData icon;
  final Color color;
}

class _BlurOrb extends StatelessWidget {
  const _BlurOrb({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0.0)],
          ),
        ),
      ),
    );
  }
}
