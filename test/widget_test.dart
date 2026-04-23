import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_learning/main.dart';
import 'package:flutter_learning/features/nas/data/nas_client.dart';
import 'package:flutter_learning/features/nas/models/nas_models.dart';
import 'package:flutter_learning/pages/acg_rss_page.dart';
import 'package:flutter_learning/pages/acg_rss_detail_parser.dart';
import 'package:flutter_learning/pages/acg_rss_parser.dart';
import 'package:flutter_learning/pages/nas_page.dart';
import 'package:flutter_learning/pages/new_anime_page.dart';
import 'package:flutter_learning/pages/new_anime_parser.dart';

class _FakeNasClient implements NasClient {
  _FakeNasClient(this.entries);

  final List<NasFileEntry> entries;

  @override
  void setProgressListener(void Function(String message)? listener) {}

  @override
  Future<List<NasFileEntry>> login({
    required String username,
    required String password,
    required String path,
  }) async {
    return entries;
  }

  @override
  Future<List<NasFileEntry>?> restoreSession({required String path}) async {
    return null;
  }

  @override
  Future<List<NasFileEntry>> listDirectory({required String path}) async {
    return entries;
  }

  @override
  Future<List<NasDownloadTask>> listDownloadTasks() async {
    return const [];
  }

  @override
  Future<void> createFolder({
    required String parentPath,
    required String folderName,
  }) async {}

  @override
  Future<void> createDownloadTask({
    required String destination,
    required String url,
  }) async {}

  @override
  Future<void> deleteDownloadTask({required String taskId}) async {}

  @override
  Future<void> logout() async {}
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('home page shows personal lab portal',
      (WidgetTester tester) async {
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
    expect(find.text('NAS 登录'), findsOneWidget);
    expect(find.text('用户名'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('nas page logs in and enters file manager', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NasPage(
          client: _FakeNasClient([
            const NasFileEntry(
              name: '项目资料',
              path: '/home/Drive/项目资料',
              isDirectory: true,
              modifiedAtLabel: '2026-04-22 10:30',
            ),
            const NasFileEntry(
              name: 'README.md',
              path: '/home/Drive/README.md',
              isDirectory: false,
              sizeLabel: '12.0 KB',
              modifiedAtLabel: '2026-04-21 18:20',
            ),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '用户名'), 'admin');
    await tester.enterText(find.widgetWithText(TextField, '密码'), '123456');
    await tester.tap(find.text('登录'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('文件管理'), findsOneWidget);
    expect(find.text('下载管理'), findsOneWidget);

    await tester.tap(find.text('文件管理'));
    await tester.pumpAndSettle();

    expect(find.text('共享目录'), findsOneWidget);
    expect(find.text('文件目录'), findsOneWidget);
    expect(find.text('项目资料'), findsOneWidget);
    expect(find.text('README.md'), findsOneWidget);
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

  testWidgets('acg rss page searches with initial keyword on first open', (
    WidgetTester tester,
  ) async {
    final searchedKeywords = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: AcgRssPage(
          initialKeyword: '测试新番',
          loader: ({required page, required keyword}) async {
            searchedKeywords.add(keyword);
            return const [
              AcgRssTopic(
                postedAt: '2026/04/22 10:00',
                category: '動畫',
                team: '测试字幕组',
                rawTitle: '测试标题',
                animeName: '测试新番',
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
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(searchedKeywords, contains('测试新番'));
    expect(find.text('测试新番'), findsNWidgets(2));
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

  testWidgets('acg rss quick link button copies primary magnet link', (
    WidgetTester tester,
  ) async {
    String? copiedText;
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
        detailUrl: '/topics/view/test-quick.html',
        magnetUrl: 'magnet:?xt=urn:btih:list',
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
          detailLoader: ({required detailUrl}) async => const AcgRssDetail(
            title: '测试标题',
            postedAt: '2026/04/22 10:00',
            size: '500MB',
            links: [
              AcgRssDownloadLink(
                label: '會員專用連接',
                url: 'https://dl.dmhy.org/test.torrent',
              ),
              AcgRssDownloadLink(
                label: 'Magnet連接',
                url: 'magnet:?xt=urn:btih:PRIMARY',
              ),
              AcgRssDownloadLink(
                label: 'Magnet連接typeII',
                url: 'magnet:?xt=urn:btih:TYPE2',
              ),
            ],
          ),
          clipboardSetter: (text) async {
            copiedText = text;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.text('快速取链'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(copiedText, 'magnet:?xt=urn:btih:PRIMARY');
    expect(find.text('已复制Magnet連接'), findsOneWidget);
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

  testWidgets('new anime nas button is disabled for future titles', (
    WidgetTester tester,
  ) async {
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
                    AnimeScheduleEntry(values: ['2027年1月2日', '未来新番', '-']),
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
          nasPageBuilder: (destination) => Scaffold(body: Text(destination)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('NAS'));
    await tester.pumpAndSettle();

    expect(find.text('/video/BD/2027-01/未来新番'), findsNothing);
  });

  testWidgets(
      'new anime nas button opens download manager destination for past titles',
      (
    WidgetTester tester,
  ) async {
    const sampleSchedule = AnimeScheduleCollection(
      years: [
        AnimeScheduleYear(
          title: '2026年新番',
          periods: [
            AnimeSchedulePeriod(
              title: '2026年1月冬季',
              groups: [
                AnimeScheduleGroup(
                  title: 'TV动画',
                  columns: ['播放时间', 'TV动画', '话数'],
                  entries: [
                    AnimeScheduleEntry(values: ['2026年1月2日', '过去新番', '-']),
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
          nasPageBuilder: (destination) => Scaffold(body: Text(destination)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('NAS'));
    await tester.pumpAndSettle();

    expect(find.text('/video/BD/2026-01/过去新番'), findsOneWidget);
  });
}
