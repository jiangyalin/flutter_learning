import 'dart:convert';

import 'package:http/http.dart' as http;

import '../pages/acg_rss_detail_parser.dart';

class AcgRssDetailService {
  const AcgRssDetailService();

  Future<AcgRssDetail> fetchDetail({required String detailUrl}) async {
    final uri = _buildDetailUri(detailUrl);
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('请求失败: ${response.statusCode}');
    }

    final html = utf8.decode(response.bodyBytes);
    return parseAcgRssDetail(html);
  }

  Uri _buildDetailUri(String detailUrl) {
    if (detailUrl.startsWith('http://') || detailUrl.startsWith('https://')) {
      return Uri.parse(detailUrl);
    }
    return Uri.https('d.acg2.icu', detailUrl);
  }
}
