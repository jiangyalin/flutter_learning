import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_learning/pages/new_anime_parser.dart';

void main() {
  test('parseAnimeScheduleCollection extracts multiple years from sample html', () {
    final html = File('test/fixtures/new_anime_sample.html').readAsStringSync();
    final collection = parseAnimeScheduleCollection(html);

    expect(collection.years, isNotEmpty);
    expect(
      collection.years.map((year) => year.title),
      containsAll(['2027年新番', '2026年新番', '2025年新番', '2024年新番']),
    );

    final year2025 = collection.years.firstWhere((year) => year.title == '2025年新番');
    expect(year2025.periods, isNotEmpty);
  });

  test('parseAnimeScheduleYear extracts 2026 schedule data from sample html', () {
    final html = File('test/fixtures/new_anime_sample.html').readAsStringSync();
    final schedule = parseAnimeScheduleYear(html, yearTitle: '2026年新番');

    expect(schedule.title, '2026年新番');
    expect(schedule.periods, isNotEmpty);
    expect(
      schedule.periods.map((period) => period.title),
      containsAll(['2026年年内未定', '2026年10月秋季', '2026年7月夏季']),
    );

    final undecided = schedule.periods.firstWhere(
      (period) => period.title == '2026年年内未定',
    );
    expect(undecided.groups.first.title, 'TV动画');
    expect(undecided.groups.first.columns, ['播放时间', 'TV动画']);
    expect(
      undecided.groups.first.entries.first.values,
      ['2026年', '在遍地都是丧尸的世界里唯独我不被袭击'],
    );

    final autumn = schedule.periods.firstWhere(
      (period) => period.title == '2026年10月秋季',
    );
    final autumnTv = autumn.groups.firstWhere((group) => group.title == 'TV动画');
    expect(autumnTv.columns, ['播放时间', 'TV动画', '话数']);
    expect(autumnTv.entries.first.values.first, '2026年10月4日');
    expect(autumnTv.entries.first.values[1], contains('蓝箱'));
  });
}
