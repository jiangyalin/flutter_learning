import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

class AcgRssTopic {
  const AcgRssTopic({
    required this.postedAt,
    required this.category,
    required this.team,
    required this.rawTitle,
    required this.animeName,
    required this.episode,
    required this.resolution,
    required this.subtitleLanguage,
    required this.detailUrl,
    required this.magnetUrl,
    required this.size,
    required this.seeders,
    required this.downloads,
    required this.completed,
    required this.publisher,
    required this.comments,
  });

  final String postedAt;
  final String category;
  final String team;
  final String rawTitle;
  final String animeName;
  final String episode;
  final String resolution;
  final String subtitleLanguage;
  final String detailUrl;
  final String magnetUrl;
  final String size;
  final String seeders;
  final String downloads;
  final String completed;
  final String publisher;
  final String comments;
}

List<AcgRssTopic> parseAcgRssTopics(String html) {
  final document = html_parser.parse(html);
  final rows = document.querySelectorAll('#topic_list tbody tr');

  return rows.map(_parseTopicRow).whereType<AcgRssTopic>().toList();
}

AcgRssTopic? _parseTopicRow(Element row) {
  final cells = row.querySelectorAll('td');
  if (cells.length < 8) {
    return null;
  }

  final postedAt = _normalizeText(cells[0].text);
  final category = _normalizeText(cells[1].text);

  final titleCell = cells[2];
  final team = _normalizeText(titleCell.querySelector('.tag a')?.text ?? '');
  final titleLink = titleCell.querySelector('a[target="_blank"]');
  final rawTitle = _normalizeText(titleLink?.text ?? '');
  final detailUrl = titleLink?.attributes['href'] ?? '';
  final comments = _normalizeText(
    titleCell.querySelector('span[style*="gray"]')?.text ?? '',
  );

  final magnetUrl =
      cells[3].querySelector('a.arrow-magnet')?.attributes['href'] ?? '';
  final size = _normalizeText(cells[4].text);
  final seeders = _normalizeText(cells[5].text);
  final downloads = _normalizeText(cells[6].text);
  final completed = _normalizeText(cells[7].text);
  final publisher = cells.length > 8 ? _normalizeText(cells[8].text) : '';

  if (rawTitle.isEmpty) {
    return null;
  }

  final parsedTitle = _parseTitle(rawTitle);

  return AcgRssTopic(
    postedAt: postedAt,
    category: category,
    team: team,
    rawTitle: rawTitle,
    animeName: parsedTitle.animeName,
    episode: parsedTitle.episode,
    resolution: parsedTitle.resolution,
    subtitleLanguage: parsedTitle.subtitleLanguage,
    detailUrl: detailUrl,
    magnetUrl: magnetUrl,
    size: size,
    seeders: seeders,
    downloads: downloads,
    completed: completed,
    publisher: publisher,
    comments: comments,
  );
}

_ParsedTitle _parseTitle(String rawTitle) {
  var working = rawTitle.trim();
  final leadingGroups = RegExp(r'^(?:\[[^\]]+\]\s*)+');
  final leadingMatch = leadingGroups.firstMatch(working);
  final leadingBracketContents = <String>[];
  if (leadingMatch != null) {
    leadingBracketContents.addAll(
      RegExp(r'\[([^\]]+)\]')
          .allMatches(leadingMatch.group(0)!)
          .map((match) => _normalizeText(match.group(1) ?? ''))
          .where((item) => item.isNotEmpty),
    );
    working = working.substring(leadingMatch.end).trim();
  }

  final bracketContents = RegExp(r'\[([^\]]+)\]')
      .allMatches(working)
      .map((match) => match.group(1)?.trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList();

  final infoSources = <String>[
    ...leadingBracketContents,
    ...bracketContents,
    working,
  ];

  final episode = _extractEpisode(infoSources);
  final resolution = _extractResolution(infoSources);
  final subtitleLanguage = _extractSubtitleLanguage(infoSources);
  final animeName = _extractAnimeName(
    rawTitle: rawTitle,
    workingTitle: working,
    leadingBracketContents: leadingBracketContents,
    bracketContents: bracketContents,
  );

  return _ParsedTitle(
    animeName: animeName,
    episode: episode,
    resolution: resolution,
    subtitleLanguage: subtitleLanguage,
  );
}

String _extractEpisode(List<String> values) {
  for (final value in values) {
    final normalized = _normalizeEpisode(value);
    if (normalized.isNotEmpty) {
      return normalized;
    }
  }
  return '';
}

String _normalizeEpisode(String value) {
  final text = _normalizeText(value);
  if (text.isEmpty) {
    return '';
  }

  final chapterMatch = RegExp(
    r'第\s*(\d+(?:\.\d+)?(?:v\d+)?)\s*(?:话|話|集)',
    caseSensitive: false,
  ).firstMatch(text);
  if (chapterMatch != null) {
    return '第${chapterMatch.group(1)}话';
  }

  final epMatch = RegExp(
    r'\bEP?\s*(\d+(?:\.\d+)?(?:v\d+)?)\s*(END)?\b',
    caseSensitive: false,
  ).firstMatch(text);
  if (epMatch != null) {
    final number = epMatch.group(1) ?? '';
    final end = (epMatch.group(2) ?? '').toUpperCase();
    return end.isEmpty ? number : '$number END';
  }

  final hyphenMatch = RegExp(
    r'\s-\s(\d+(?:\.\d+)?(?:v\d+)?)(?:\s*(END))?(?=\s*(?:\[|$))',
    caseSensitive: false,
  ).firstMatch(text);
  if (hyphenMatch != null) {
    final number = hyphenMatch.group(1) ?? '';
    final end = (hyphenMatch.group(2) ?? '').toUpperCase();
    return end.isEmpty ? number : '$number END';
  }

  final suffixMatch = RegExp(
    r'(?:^|[\\/\-\s])(\d+(?:\.\d+)?(?:v\d+)?)\s*(END)?$',
    caseSensitive: false,
  ).firstMatch(text);
  if (suffixMatch != null && !_looksLikeResolution(text)) {
    final number = suffixMatch.group(1) ?? '';
    final end = (suffixMatch.group(2) ?? '').toUpperCase();
    return end.isEmpty ? number : '$number END';
  }

  if (RegExp(r'^\d+(?:\.\d+)?(?:v\d+)?(?:\s*END)?$', caseSensitive: false)
      .hasMatch(text)) {
    return text.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  return '';
}

String _extractResolution(List<String> values) {
  for (final value in values) {
    final match = RegExp(r'(\d{3,4}\s*[pPiI])').firstMatch(value);
    if (match != null) {
      return _normalizeText(match.group(1)!).toUpperCase();
    }
  }
  return '';
}

String _extractSubtitleLanguage(List<String> values) {
  for (final value in values) {
    if (_looksLikeSubtitleLanguage(value)) {
      return _normalizeSubtitleLanguage(value);
    }
  }
  return '';
}

String _normalizeSubtitleLanguage(String value) {
  var text = _normalizeText(value);

  final aliasMap = <String, String>{
    'CHS': '简中',
    'GB': '简中',
    'SC': '简中',
    'CHT': '繁中',
    'BIG5': '繁中',
    'TC': '繁中',
    'JP': '日语',
    'JPN': '日语',
    'JAP': '日语',
  };

  for (final entry in aliasMap.entries) {
    text = text.replaceAll(
      RegExp('\\b${entry.key}\\b', caseSensitive: false),
      entry.value,
    );
  }

  text = text
      .replaceAll('&', '+')
      .replaceAll(RegExp(r'\s*/\s*'), '+')
      .replaceAll(RegExp(r'\s*\+\s*'), '+')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  if (text.contains('无字幕') || text.contains('無字幕')) {
    return text.contains('無字幕') ? '無字幕' : '无字幕';
  }

  return text;
}

String _extractAnimeName({
  required String rawTitle,
  required String workingTitle,
  required List<String> leadingBracketContents,
  required List<String> bracketContents,
}) {
  final candidates = <String>[];

  for (final item in leadingBracketContents) {
    if (_isPotentialTitleCandidate(item)) {
      candidates.add(item);
    }
  }

  for (final item in bracketContents) {
    if (_isPotentialTitleCandidate(item)) {
      candidates.add(item);
    }
  }

  candidates.addAll(_splitTitleCandidates(workingTitle));

  final cleanedCandidates = candidates
      .map(_cleanupTitleCandidate)
      .where((item) => item.isNotEmpty)
      .toList();

  if (cleanedCandidates.isEmpty) {
    return _cleanupTitleCandidate(rawTitle);
  }

  cleanedCandidates.sort((a, b) {
    final scoreCompare = _titleCandidateScore(b).compareTo(
      _titleCandidateScore(a),
    );
    if (scoreCompare != 0) {
      return scoreCompare;
    }
    return a.length.compareTo(b.length);
  });

  return cleanedCandidates.first;
}

List<String> _splitTitleCandidates(String workingTitle) {
  final withoutBrackets = workingTitle.replaceAll(RegExp(r'\[[^\]]+\]'), ' ');
  final normalized = _normalizeText(withoutBrackets);
  if (normalized.isEmpty) {
    return const [];
  }

  final parts = normalized
      .split(RegExp(r'\s*/\s*'))
      .expand((part) => part.split(RegExp(r'\s{2,}')))
      .map(_normalizeText)
      .where((item) => item.isNotEmpty)
      .toList();

  return parts.isEmpty ? [normalized] : parts;
}

bool _isPotentialTitleCandidate(String value) {
  final text = _normalizeText(value);
  if (text.isEmpty) {
    return false;
  }
  if (_looksLikeMetadataOnly(text) || _normalizeEpisode(text).isNotEmpty) {
    return false;
  }
  return text.runes.any(_looksLikeTitleRune);
}

String _cleanupTitleCandidate(String value) {
  var text = _normalizeText(value);
  if (text.isEmpty) {
    return '';
  }

  text = text
      .replaceAll(RegExp(r'^\[[^\]]+\]\s*'), '')
      .replaceAll(RegExp(r'\[[^\]]*检索[^\]]*\]', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\[[^\]]*檢索[^\]]*\]', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\[[^\]]+\]'), ' ')
      .replaceAll(RegExp(r'\(\s*[^\)]*检索[^\)]*\)', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\(\s*[^\)]*檢索[^\)]*\)', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\s+-\s+\d+(?:\.\d+)?(?:v\d+)?(?:\s*END)?$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\bEP?\s*\d+(?:\.\d+)?(?:v\d+)?(?:\s*END)?$', caseSensitive: false), '')
      .replaceAll(RegExp(r'第\s*\d+(?:\.\d+)?(?:v\d+)?\s*(?:话|話|集)$'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  final slashParts = text
      .split(RegExp(r'\s*/\s*'))
      .map(_normalizeText)
      .where((item) => item.isNotEmpty)
      .toList();
  if (slashParts.length > 1) {
    slashParts.sort((a, b) => _titleCandidateScore(b).compareTo(_titleCandidateScore(a)));
    text = slashParts.first;
  }

  return text;
}

int _titleCandidateScore(String value) {
  final text = _normalizeText(value);
  if (text.isEmpty) {
    return -999;
  }

  var score = 0;
  if (RegExp(r'[\u4e00-\u9fff]').hasMatch(text)) {
    score += 6;
  }
  if (RegExp(r'[\u3040-\u30ff]').hasMatch(text)) {
    score += 4;
  }
  if (RegExp(r'[A-Za-z]').hasMatch(text)) {
    score += 2;
  }
  if (text.contains('第') && text.contains('季')) {
    score += 2;
  }
  if (_looksLikeMetadataOnly(text)) {
    score -= 10;
  }

  return score;
}

bool _looksLikeMetadataOnly(String value) {
  final text = _normalizeText(value);
  if (text.isEmpty) {
    return true;
  }

  if (_looksLikeResolution(text) || _looksLikeSubtitleLanguage(text)) {
    return true;
  }

  const metadataKeywords = [
    'WEB-DL',
    'WEBRIP',
    'BDRIP',
    'DVDRIP',
    'HEVC',
    'AVC',
    'AAC',
    'FLAC',
    'MP4',
    'MKV',
    'Baha',
    '檢索',
    '检索',
    '新番',
    '字幕组',
    '字幕組',
  ];

  for (final keyword in metadataKeywords) {
    if (text.toUpperCase().contains(keyword.toUpperCase())) {
      return true;
    }
  }

  return false;
}

bool _looksLikeResolution(String value) {
  return RegExp(r'\b\d{3,4}\s*[pPiI]\b').hasMatch(value);
}

bool _looksLikeSubtitleLanguage(String value) {
  final text = _normalizeText(value);
  if (text.contains('字幕组') || text.contains('字幕組')) {
    return false;
  }

  return text.contains('简') ||
      text.contains('繁') ||
      text.contains('简中') ||
      text.contains('繁中') ||
      text.contains('日语') ||
      text.contains('日文') ||
      text.contains('日雙語') ||
      text.contains('日双语') ||
      (text.contains('字幕') &&
          !text.contains('字幕组') &&
          !text.contains('字幕組')) ||
      text.contains('雙語') ||
      text.contains('双语') ||
      text.contains('內嵌') ||
      text.contains('內封') ||
      text.contains('内嵌') ||
      text.contains('内封') ||
      text.contains('无字幕') ||
      text.contains('無字幕') ||
      RegExp(r'\b(CHS|CHT|GB|BIG5|JP|JPN)\b', caseSensitive: false)
          .hasMatch(text);
}

bool _looksLikeTitleRune(int rune) {
  return (rune >= 0x4E00 && rune <= 0x9FFF) ||
      (rune >= 0x3040 && rune <= 0x30FF) ||
      (rune >= 0x0041 && rune <= 0x005A) ||
      (rune >= 0x0061 && rune <= 0x007A);
}

String _normalizeText(String value) {
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

class _ParsedTitle {
  const _ParsedTitle({
    required this.animeName,
    required this.episode,
    required this.resolution,
    required this.subtitleLanguage,
  });

  final String animeName;
  final String episode;
  final String resolution;
  final String subtitleLanguage;
}
