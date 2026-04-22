import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'acg_rss_page.dart';
import 'new_anime_parser.dart';

class NewAnimePage extends StatefulWidget {
  const NewAnimePage({
    super.key,
    this.loader = _fetchAnimeSchedule,
    this.rssPageBuilder = _buildRssPage,
  });

  final Future<AnimeScheduleCollection> Function() loader;
  final Widget Function(String keyword) rssPageBuilder;

  static Future<AnimeScheduleCollection> _fetchAnimeSchedule() async {
    final response = await http.get(
      Uri.parse(
        'https://baike.baidu.com/item/%E5%8A%A8%E7%94%BB%E6%96%B0%E7%95%AA/22725827',
      ),
      headers: const {
        'User-Agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'Accept-Language': 'zh-CN,zh;q=0.9',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('请求失败: ${response.statusCode}');
    }

    final html = utf8.decode(response.bodyBytes);
    return parseAnimeScheduleCollection(html);
  }

  static Widget _buildRssPage(String keyword) {
    return AcgRssPage(initialKeyword: keyword);
  }

  @override
  State<NewAnimePage> createState() => _NewAnimePageState();
}

class _NewAnimePageState extends State<NewAnimePage> {
  bool _isLoading = true;
  String? _errorMessage;
  AnimeScheduleCollection? _schedule;

  @override
  void initState() {
    super.initState();
    _loadSchedule();
  }

  Future<void> _loadSchedule() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final schedule = await widget.loader();
      if (!mounted) {
        return;
      }

      setState(() {
        _schedule = schedule;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = '加载失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _openRssPage(String title) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => widget.rssPageBuilder(title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('新番')),
      body: RefreshIndicator(
        onRefresh: _loadSchedule,
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading && _schedule == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _schedule == null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _ErrorCard(
            message: _errorMessage!,
            onRetry: _loadSchedule,
          ),
        ],
      );
    }

    final schedule = _schedule;
    if (schedule == null) {
      return ListView(
        children: const [
          SizedBox(height: 120),
          Center(child: Text('暂无数据')),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      children: [
        for (final year in schedule.years) ...[
          _YearSection(
            year: year,
            onOpenRss: _openRssPage,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _YearSection extends StatelessWidget {
  const _YearSection({
    required this.year,
    required this.onOpenRss,
  });

  final AnimeScheduleYear year;
  final ValueChanged<String> onOpenRss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            year.title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF9A3412),
            ),
          ),
          const SizedBox(height: 10),
          for (var index = 0; index < year.periods.length; index++) ...[
            _PeriodSection(
              period: year.periods[index],
              onOpenRss: onOpenRss,
            ),
            if (index != year.periods.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _PeriodSection extends StatelessWidget {
  const _PeriodSection({
    required this.period,
    required this.onOpenRss,
  });

  final AnimeSchedulePeriod period;
  final ValueChanged<String> onOpenRss;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          period.title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 8),
        for (var index = 0; index < period.groups.length; index++) ...[
          _GroupSection(
            group: period.groups[index],
            onOpenRss: onOpenRss,
          ),
          if (index != period.groups.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _GroupSection extends StatelessWidget {
  const _GroupSection({
    required this.group,
    required this.onOpenRss,
  });

  final AnimeScheduleGroup group;
  final ValueChanged<String> onOpenRss;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFFEA580C),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              group.title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final entry in group.entries) ...[
          _AnimeEntryCard(
            columns: group.columns,
            entry: entry,
            onOpenRss: onOpenRss,
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _AnimeEntryCard extends StatelessWidget {
  const _AnimeEntryCard({
    required this.columns,
    required this.entry,
    required this.onOpenRss,
  });

  final List<String> columns;
  final AnimeScheduleEntry entry;
  final ValueChanged<String> onOpenRss;

  @override
  Widget build(BuildContext context) {
    final timeIndex = columns.isNotEmpty ? 0 : -1;
    final titleIndex = columns.length > 1 ? 1 : 0;
    final timeText =
        timeIndex >= 0 && timeIndex < entry.values.length ? entry.values[timeIndex] : '';
    final title = titleIndex < entry.values.length ? entry.values[titleIndex] : '-';
    final airStatus = _resolveAirStatus(timeText);

    final detailPairs = <MapEntry<String, String>>[];
    for (var index = 0; index < columns.length && index < entry.values.length; index++) {
      if (index == titleIndex || index == timeIndex) {
        continue;
      }

      final value = entry.values[index];
      if (value.isEmpty || value == '-') {
        continue;
      }
      detailPairs.add(MapEntry(columns[index], value));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (timeText.isNotEmpty)
            SizedBox(
              width: 90,
              child: Text(
                timeText,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: airStatus.timeColor,
                  height: 1.35,
                ),
              ),
            ),
          if (timeText.isNotEmpty) const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                    height: 1.3,
                  ),
                ),
                if (detailPairs.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    detailPairs
                        .map((pair) => '${pair.key} ${pair.value}')
                        .join('  ·  '),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF667085),
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            children: [
              _ActionButton(
                label: 'RSS',
                backgroundColor: const Color(0xFFE0F2FE),
                foregroundColor: const Color(0xFF0369A1),
                onTap: () => onOpenRss(title),
              ),
              const SizedBox(height: 6),
              _ActionButton(
                label: 'NAS',
                backgroundColor: const Color(0xFFECFDF3),
                foregroundColor: const Color(0xFF027A48),
                onTap: () => _showActionHint(context, 'NAS', title),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

void _showActionHint(BuildContext context, String action, String title) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('$action: $title'),
        behavior: SnackBarBehavior.floating,
      ),
    );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onTap,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 26,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          elevation: 0,
          padding: EdgeInsets.zero,
          minimumSize: const Size(48, 26),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

enum _AirState {
  aired,
  upcoming,
  unknown,
}

class _AirStatus {
  const _AirStatus({
    required this.state,
    required this.timeColor,
  });

  final _AirState state;
  final Color timeColor;
}

_AirStatus _resolveAirStatus(String timeText) {
  final normalized = timeText.trim();
  if (normalized.isEmpty) {
    return _unknownStatus();
  }

  final exactDayMatch = RegExp(r'^(\d{4})年(\d{1,2})月(\d{1,2})日$').firstMatch(normalized);
  if (exactDayMatch != null) {
    final date = DateTime(
      int.parse(exactDayMatch.group(1)!),
      int.parse(exactDayMatch.group(2)!),
      int.parse(exactDayMatch.group(3)!),
    );
    return _fromDate(date);
  }

  final monthMatch = RegExp(r'^(\d{4})年(\d{1,2})月$').firstMatch(normalized);
  if (monthMatch != null) {
    final date = DateTime(
      int.parse(monthMatch.group(1)!),
      int.parse(monthMatch.group(2)!),
      1,
    );
    return _fromDate(date);
  }

  if (RegExp(r'^\d{4}年$').hasMatch(normalized)) {
    return _unknownStatus();
  }

  return _unknownStatus();
}

_AirStatus _fromDate(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  if (date.isAfter(today)) {
    return _upcomingStatus();
  }
  return _airedStatus();
}

_AirStatus _airedStatus() {
  return const _AirStatus(
    state: _AirState.aired,
    timeColor: Color(0xFF047857),
  );
}

_AirStatus _upcomingStatus() {
  return const _AirStatus(
    state: _AirState.upcoming,
    timeColor: Color(0xFFD97706),
  );
}

_AirStatus _unknownStatus() {
  return const _AirStatus(
    state: _AirState.unknown,
    timeColor: Color(0xFF475467),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '加载失败',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFFB42318),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: Color(0xFF667085),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: onRetry,
            child: const Text('重新加载'),
          ),
        ],
      ),
    );
  }
}
