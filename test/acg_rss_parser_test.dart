import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_learning/pages/acg_rss_detail_parser.dart';
import 'package:flutter_learning/pages/acg_rss_parser.dart';

void main() {
  test('parseAcgRssTopics extracts topic rows from html table', () {
    const html = '''
      <table id="topic_list">
        <tbody>
          <tr>
            <td>2026/03/31 18:09</td>
            <td><a><font>動畫</font></a></td>
            <td class="title">
              <span class="tag"><a href="/topics/list/team_id/619">桜都字幕组</a></span>
              <a href="/topics/view/715948_test.html" target="_blank">[桜都字幕组] 我推的孩子 第三季 [11v2]</a>
              <span style="color: gray;">約3條評論</span>
            </td>
            <td><a class="download-arrow arrow-magnet" href="magnet:?xt=urn:btih:TEST123">&nbsp;</a></td>
            <td>964.6MB</td>
            <td><span class="btl_1">12</span></td>
            <td><span class="bts_1">34</span></td>
            <td>56</td>
            <td><a href="/topics/list/user_id/676357">sakurato</a></td>
          </tr>
        </tbody>
      </table>
    ''';

    final topics = parseAcgRssTopics(html);

    expect(topics, hasLength(1));
    expect(topics.first.postedAt, '2026/03/31 18:09');
    expect(topics.first.category, '動畫');
    expect(topics.first.team, '桜都字幕组');
    expect(topics.first.rawTitle, contains('我推的孩子'));
    expect(topics.first.animeName, '我推的孩子 第三季');
    expect(topics.first.episode, '11v2');
    expect(topics.first.resolution, '');
    expect(topics.first.subtitleLanguage, '');
    expect(topics.first.detailUrl, '/topics/view/715948_test.html');
    expect(topics.first.magnetUrl, 'magnet:?xt=urn:btih:TEST123');
    expect(topics.first.size, '964.6MB');
    expect(topics.first.downloads, '34');
    expect(topics.first.completed, '56');
    expect(topics.first.publisher, 'sakurato');
    expect(topics.first.comments, '約3條評論');
  });

  test('parseAcgRssTopics extracts episode resolution and subtitle language', () {
    const html = '''
      <table id="topic_list">
        <tbody>
          <tr>
            <td>2026/03/31 18:09</td>
            <td><a><font>動畫</font></a></td>
            <td class="title">
              <span class="tag"><a href="/topics/list/team_id/619">桜都字幕组</a></span>
              <a href="/topics/view/715948_test.html" target="_blank">[桜都字幕组] 我推的孩子 第三季 / Oshi no Ko 3rd Season [11v2][1080P][简繁日内封]</a>
            </td>
            <td><a class="download-arrow arrow-magnet" href="magnet:?xt=urn:btih:TEST123">&nbsp;</a></td>
            <td>964.6MB</td>
            <td><span class="btl_1">1</span></td>
            <td><span class="bts_1">2</span></td>
            <td>3</td>
            <td><a href="/topics/list/user_id/676357">sakurato</a></td>
          </tr>
        </tbody>
      </table>
    ''';

    final topic = parseAcgRssTopics(html).first;

    expect(topic.animeName, '我推的孩子 第三季');
    expect(topic.episode, '11v2');
    expect(topic.resolution, '1080P');
    expect(topic.subtitleLanguage, '简繁日内封');
  });

  test('parseAcgRssTopics formats real-world title variants from first page', () {
    const html = '''
      <table id="topic_list">
        <tbody>
          <tr>
            <td>今天 15:01</td>
            <td><a><font>動畫</font></a></td>
            <td class="title">
              <span class="tag"><a href="/topics/list/team_id/827">亿次研同好会</a></span>
              <a href="/topics/view/717423_test.html" target="_blank">[Billion Meta Lab] 魔法姐妹露露莉莉 Mahou no Shimai Rurutto Riryi [03][1080P][HEVC-10bit][CHS&amp;CHT &amp;JP ][检索：魔法姐妹露露特莉莉]</a>
            </td>
            <td><a class="download-arrow arrow-magnet" href="magnet:?xt=urn:btih:TEST001">&nbsp;</a></td>
            <td>404.9MB</td>
            <td>-</td>
            <td>-</td>
            <td>-</td>
            <td><a>pianolibrary</a></td>
          </tr>
          <tr>
            <td>今天 13:19</td>
            <td><a><font>動畫</font></a></td>
            <td class="title">
              <span class="tag"><a href="/topics/list/team_id/283">千夏字幕组</a></span>
              <a href="/topics/view/717418_test.html" target="_blank">[千夏字幕組][上伊那牡丹，醉姿如百合_Kamiina Botan, Yoeru Sugata wa Yuri no Hana][第02話][1080p_AVC][繁體]</a>
            </td>
            <td><a class="download-arrow arrow-magnet" href="magnet:?xt=urn:btih:TEST002">&nbsp;</a></td>
            <td>271.8MB</td>
            <td>-</td>
            <td>-</td>
            <td>-</td>
            <td><a>千夏字幕组</a></td>
          </tr>
          <tr>
            <td>今天 12:15</td>
            <td><a><font>動畫</font></a></td>
            <td class="title">
              <span class="tag"><a href="/topics/list/team_id/657">LoliHouse</a></span>
              <a href="/topics/view/717413_test.html" target="_blank">[LoliHouse] 魔法姊妹露露特莉莉 / Magical Sisters LuluttoLilly - 03 [WebRip 1080p HEVC-10bit AAC][简繁内封字幕]</a>
            </td>
            <td><a class="download-arrow arrow-magnet" href="magnet:?xt=urn:btih:TEST003">&nbsp;</a></td>
            <td>572.7MB</td>
            <td>-</td>
            <td>-</td>
            <td>-</td>
            <td><a>LoliHouse</a></td>
          </tr>
        </tbody>
      </table>
    ''';

    final topics = parseAcgRssTopics(html);

    expect(topics, hasLength(3));

    expect(topics[0].animeName, '魔法姐妹露露莉莉 Mahou no Shimai Rurutto Riryi');
    expect(topics[0].episode, '03');
    expect(topics[0].resolution, '1080P');
    expect(topics[0].subtitleLanguage, '简中+繁中+日语');

    expect(topics[1].animeName, '上伊那牡丹，醉姿如百合_Kamiina Botan, Yoeru Sugata wa Yuri no Hana');
    expect(topics[1].episode, '第02话');
    expect(topics[1].resolution, '1080P');
    expect(topics[1].subtitleLanguage, '繁體');

    expect(topics[2].animeName, '魔法姊妹露露特莉莉');
    expect(topics[2].episode, '03');
    expect(topics[2].resolution, '1080P');
    expect(topics[2].subtitleLanguage, '简繁内封字幕');
  });

  test('parseAcgRssDetail extracts download links from detail page', () {
    const html = '''
      <div class="topic-title">
        <h3>测试资源标题</h3>
        <div class="resource-info">
          <ul>
            <li>發佈時間: <span>2026/04/20 15:01</span></li>
            <li>文件大小: <span>404.9MB</span></li>
          </ul>
        </div>
      </div>
      <div id="resource-tabs">
        <div id="tabs-1">
          <p>
            <strong>會員專用連接:</strong>
            <a href="//dl.dmhy.org/2026/04/20/test.torrent">torrent</a>
          </p>
          <p>
            <strong>Magnet連接:</strong>
            <a href="magnet:?xt=urn:btih:ABC123">magnet 1</a>
          </p>
          <p>
            <strong>Magnet連接typeII: </strong>
            <a href="magnet:?xt=urn:btih:XYZ789">magnet 2</a>
          </p>
          <p>
            <strong>迅雷下載: </strong>
            <a href="javascript:void(0);">xunlei</a>
          </p>
        </div>
      </div>
    ''';

    final detail = parseAcgRssDetail(html);

    expect(detail.title, '测试资源标题');
    expect(detail.postedAt, '2026/04/20 15:01');
    expect(detail.size, '404.9MB');
    expect(detail.links, hasLength(3));
    expect(detail.links[0].label, '會員專用連接');
    expect(detail.links[0].url, 'https://dl.dmhy.org/2026/04/20/test.torrent');
    expect(detail.links[1].label, 'Magnet連接');
    expect(detail.links[1].url, 'magnet:?xt=urn:btih:ABC123');
    expect(detail.links[2].label, 'Magnet連接typeII');
    expect(detail.links[2].url, 'magnet:?xt=urn:btih:XYZ789');
  });
}
