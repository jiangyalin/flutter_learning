import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

class AcgRssDownloadLink {
  const AcgRssDownloadLink({
    required this.label,
    required this.url,
  });

  final String label;
  final String url;
}

class AcgRssDetail {
  const AcgRssDetail({
    required this.title,
    required this.postedAt,
    required this.size,
    required this.links,
  });

  final String title;
  final String postedAt;
  final String size;
  final List<AcgRssDownloadLink> links;
}

AcgRssDetail parseAcgRssDetail(String html) {
  final document = html_parser.parse(html);

  final title = _normalizeText(document.querySelector('.topic-title h3')?.text ?? '');
  final infoItems = document.querySelectorAll('.topic-title .resource-info li');

  var postedAt = '';
  var size = '';

  for (final item in infoItems) {
    final text = _normalizeText(item.text);
    if (text.startsWith('發佈時間') || text.startsWith('发布时间')) {
      postedAt = _extractValue(item);
    } else if (text.startsWith('文件大小')) {
      size = _extractValue(item);
    }
  }

  final links = <AcgRssDownloadLink>[];
  final seen = <String>{};
  final paragraphs = document.querySelectorAll('#resource-tabs #tabs-1 p');

  for (final paragraph in paragraphs) {
    final strong = paragraph.querySelector('strong');
    final anchor = paragraph.querySelector('a[href]');
    if (strong == null || anchor == null) {
      continue;
    }

    final label = _normalizeLabel(strong.text);
    final rawUrl = _normalizeUrl(anchor.attributes['href'] ?? '');
    if (label.isEmpty || rawUrl.isEmpty || !_isUsefulDownloadLink(label, rawUrl)) {
      continue;
    }

    final key = '$label|$rawUrl';
    if (seen.add(key)) {
      links.add(AcgRssDownloadLink(label: label, url: rawUrl));
    }
  }

  return AcgRssDetail(
    title: title,
    postedAt: postedAt,
    size: size,
    links: links,
  );
}

String _extractValue(Element element) {
  final span = element.querySelector('span');
  if (span != null) {
    return _normalizeText(span.text);
  }

  final text = _normalizeText(element.text);
  final parts = text.split(RegExp(r'[:：]'));
  if (parts.length < 2) {
    return text;
  }
  return _normalizeText(parts.sublist(1).join(':'));
}

String _normalizeLabel(String value) {
  return _normalizeText(value).replaceAll(RegExp(r'[:：]+$'), '');
}

String _normalizeUrl(String value) {
  final text = value.trim();
  if (text.isEmpty || text == '#' || text.startsWith('javascript:')) {
    return '';
  }
  if (text.startsWith('//')) {
    return 'https:$text';
  }
  return text;
}

bool _isUsefulDownloadLink(String label, String url) {
  if (url.startsWith('magnet:')) {
    return true;
  }
  if (url.startsWith('http://') || url.startsWith('https://')) {
    return label.contains('會員專用連接') ||
        label.contains('专用连接') ||
        label.contains('Magnet連接') ||
        label.contains('Magnet连接') ||
        label.contains('Magnet連接typeII') ||
        label.contains('Magnet连接typeII') ||
        url.endsWith('.torrent');
  }
  return false;
}

String _normalizeText(String value) {
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}
