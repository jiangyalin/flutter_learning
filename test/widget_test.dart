import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_learning/main.dart';
import 'package:flutter_learning/pages/acg_rss_page.dart';
import 'package:flutter_learning/pages/acg_rss_parser.dart';
import 'package:flutter_learning/pages/nas_page.dart';
import 'package:flutter_learning/pages/new_anime_page.dart';
import 'package:flutter_learning/pages/new_anime_parser.dart';

void main() {
  testWidgets('home page shows personal lab portal', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('我的实验应用'), findsOneWidget);
    expect(find.text('所有功能入口都平铺在这里'), findsOneWidget);
    expect(find.text('ACG RSS'), findsOneWidget);
    expect(find.text('新番'), findsOneWidget);
    expect(find.text('NAS'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('实验开关'),
      300,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();

    expect(find.text('实验开关'), findsOneWidget);
  });

  testWidgets('nas page opens from home', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('NAS'),
      300,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('NAS'));
    await tester.pumpAndSettle();

    expect(find.byType(NasPage), findsOneWidget);
    expect(find.text('NAS'), findsWidgets);
  });

  testWidgets('acg rss page auto loads and shows search field', (
    WidgetTester tester,
  ) async {
    const sampleTopics = [
      AcgRssTopic(
        postedAt: '2026/04/22 10:00',
        category: '動畫',
        team: '测试字幕组',
        rawTitle: '测试标题',
        animeName: '测试动画',
        episode: '01',
        resolution: '1080P',
        subtitleLanguage: '简繁',
        detailUrl: '/topics/view/test.html',
        magnetUrl: 'magnet:?xt=urn:btih:test',
        size: '500MB',
        seeders: '1',
        downloads: '2',
        completed: '3',
        publisher: 'tester',
        comments: '',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: AcgRssPage(
          loader: ({required page, required keyword}) async => sampleTopics,
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('输入关键字搜索'), findsOneWidget);
    expect(find.text('测试动画'), findsOneWidget);
  });

  testWidgets('acg rss topic card opens detail page', (
    WidgetTester tester,
  ) async {
    const sampleTopics = [
      AcgRssTopic(
        postedAt: '2026/04/22 10:00',
        category: '動畫',
        team: '测试字幕组',
        rawTitle: '测试标题',
        animeName: '测试动画',
        episode: '01',
        resolution: '1080P',
        subtitleLanguage: '简繁',
        detailUrl: '/topics/view/test.html',
        magnetUrl: 'magnet:?xt=urn:btih:test',
        size: '500MB',
        seeders: '1',
        downloads: '2',
        completed: '3',
        publisher: 'tester',
        comments: '',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: AcgRssPage(
          loader: ({required page, required keyword}) async => sampleTopics,
          detailPageBuilder: (topic) => Scaffold(
            appBar: AppBar(title: const Text('详情')),
            body: Text(topic.detailUrl),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.text('测试动画'));
    await tester.pumpAndSettle();

    expect(find.text('详情'), findsOneWidget);
    expect(find.text('/topics/view/test.html'), findsOneWidget);
  });

  testWidgets('acg rss topic card toggles raw title visibility', (
    WidgetTester tester,
  ) async {
    const sampleTopics = [
      AcgRssTopic(
        postedAt: '2026/04/22 10:00',
        category: '動畫',
        team: '测试字幕组',
        rawTitle: '[测试字幕组] 这是一条完整原始标题 [01][1080P][简繁]',
        animeName: '测试动画',
        episode: '01',
        resolution: '1080P',
        subtitleLanguage: '简繁',
        detailUrl: '/topics/view/test.html',
        magnetUrl: 'magnet:?xt=urn:btih:test',
        size: '500MB',
        seeders: '1',
        downloads: '2',
        completed: '3',
        publisher: 'tester',
        comments: '',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: AcgRssPage(
          loader: ({required page, required keyword}) async => sampleTopics,
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('[测试字幕组] 这是一条完整原始标题 [01][1080P][简繁]'), findsNothing);

    await tester.tap(find.text('查看原始名'));
    await tester.pumpAndSettle();

    expect(find.text('[测试字幕组] 这是一条完整原始标题 [01][1080P][简繁]'), findsOneWidget);
    expect(find.text('隐藏原始名'), findsOneWidget);
  });

  testWidgets('acg rss fetch-link button opens detail page', (
    WidgetTester tester,
  ) async {
    const sampleTopics = [
      AcgRssTopic(
        postedAt: '2026/04/22 10:00',
        category: '動畫',
        team: '测试字幕组',
        rawTitle: '测试标题',
        animeName: '测试动画',
        episode: '01',
        resolution: '1080P',
        subtitleLanguage: '简繁',
        detailUrl: '/topics/view/test-button.html',
        magnetUrl: 'magnet:?xt=urn:btih:test',
        size: '500MB',
        seeders: '1',
        downloads: '2',
        completed: '3',
        publisher: 'tester',
        comments: '',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: AcgRssPage(
          loader: ({required page, required keyword}) async => sampleTopics,
          detailPageBuilder: (topic) => Scaffold(
            appBar: AppBar(title: const Text('详情')),
            body: Text(topic.detailUrl),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.text('取链'));
    await tester.pumpAndSettle();

    expect(find.text('详情'), findsOneWidget);
    expect(find.text('/topics/view/test-button.html'), findsOneWidget);
  });

  testWidgets('new anime page opens from home', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    const sampleSchedule = AnimeScheduleCollection(
      years: [
        AnimeScheduleYear(
          title: '2027年新番',
          periods: [
            AnimeSchedulePeriod(
              title: '2027年1月冬季',
              groups: [
                AnimeScheduleGroup(
                  title: 'TV动画',
                  columns: ['播放时间', 'TV动画', '话数'],
                  entries: [
                    AnimeScheduleEntry(values: ['2027年1月', '测试新番 A', '-']),
                  ],
                ),
              ],
            ),
          ],
        ),
        AnimeScheduleYear(
          title: '2026年新番',
          periods: [
            AnimeSchedulePeriod(
              title: '2026年7月夏季',
              groups: [
                AnimeScheduleGroup(
                  title: 'TV动画',
                  columns: ['播放时间', 'TV动画', '话数'],
                  entries: [
                    AnimeScheduleEntry(
                      values: ['2026年7月2日', '被追放的转生重骑士用游戏知识开无双', '-'],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );

    await tester.tap(find.text('新番'));
    await tester.pumpWidget(
      MaterialApp(
        home: NewAnimePage(loader: () async => sampleSchedule),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2027年新番'), findsOneWidget);
    expect(find.text('测试新番 A'), findsOneWidget);
    expect(find.text('2026年7月夏季'), findsOneWidget);
    expect(find.text('被追放的转生重骑士用游戏知识开无双'), findsOneWidget);
  });

  testWidgets('new anime rss button opens acg rss with title keyword', (
    WidgetTester tester,
  ) async {
    const sampleSchedule = AnimeScheduleCollection(
      years: [
        AnimeScheduleYear(
          title: '2026年新番',
          periods: [
            AnimeSchedulePeriod(
              title: '2026年7月夏季',
              groups: [
                AnimeScheduleGroup(
                  title: 'TV动画',
                  columns: ['播放时间', 'TV动画', '话数'],
                  entries: [
                    AnimeScheduleEntry(
                      values: ['2026年7月2日', '被追放的转生重骑士用游戏知识开无双', '-'],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NewAnimePage(
          loader: () async => sampleSchedule,
          rssPageBuilder: (keyword) => AcgRssPage(
            initialKeyword: keyword,
            loader: ({required page, required keyword}) async => const [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('RSS'));
    await tester.pumpAndSettle();

    expect(find.text('ACG RSS'), findsOneWidget);
    expect(find.text('被追放的转生重骑士用游戏知识开无双'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

}
