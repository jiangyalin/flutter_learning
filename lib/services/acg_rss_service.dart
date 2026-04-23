import 'dart:convert';

import 'package:http/http.dart' as http;

import '../pages/acg_rss_parser.dart';

class AcgRssService {
  const AcgRssService();

  Future<List<AcgRssTopic>> fetchTopics({
    required int page,
    required String keyword,
  }) async {
    const baseHost = 'd.acg2.icu';
    const basePath = '/topics/list';
    const order = 'date-desc';

    final path = page <= 1 ? basePath : '$basePath/page/$page';
    final query = <String, String>{'order': order};
    if (keyword.trim().isNotEmpty) {
      query['keyword'] = keyword.trim();
    }

    final response = await http.get(
      Uri.https(baseHost, path, query),
      headers: const {
        'User-Agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,zh-TW;q=0.8,en;q=0.7',
        'Referer': 'https://d.acg2.icu/topics/list',
      },
    );
    if (response.statusCode != 200) {
      throw Exception('请求失败: ${response.statusCode}');
    }

    final html = utf8.decode(response.bodyBytes);
    return parseAcgRssTopics(html);
  }
}
