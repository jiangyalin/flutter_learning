import 'dart:convert';

import 'package:http/http.dart' as http;

import '../pages/new_anime_parser.dart';

class NewAnimeService {
  const NewAnimeService();

  Future<AnimeScheduleCollection> fetchAnimeSchedule() async {
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
}
