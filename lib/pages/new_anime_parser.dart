import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

class AnimeScheduleCollection {
  const AnimeScheduleCollection({
    required this.years,
  });

  final List<AnimeScheduleYear> years;
}

class AnimeScheduleYear {
  const AnimeScheduleYear({
    required this.title,
    required this.periods,
  });

  final String title;
  final List<AnimeSchedulePeriod> periods;
}

class AnimeSchedulePeriod {
  const AnimeSchedulePeriod({
    required this.title,
    required this.groups,
  });

  final String title;
  final List<AnimeScheduleGroup> groups;
}

class AnimeScheduleGroup {
  const AnimeScheduleGroup({
    required this.title,
    required this.columns,
    required this.entries,
  });

  final String title;
  final List<String> columns;
  final List<AnimeScheduleEntry> entries;
}

class AnimeScheduleEntry {
  const AnimeScheduleEntry({
    required this.values,
  });

  final List<String> values;
}

AnimeScheduleCollection parseAnimeScheduleCollection(String html) {
  final years = <AnimeScheduleYear>[];
  final headingPattern = RegExp(r'<h2>((?:\d{4}(?:-\d{4})?|未定播放时间)年?新番|未定播放时间)</h2>');
  final matches = headingPattern.allMatches(html).toList();

  for (var index = 0; index < matches.length; index++) {
    final yearTitle = matches[index].group(1);
    if (yearTitle == null || yearTitle.isEmpty) {
      continue;
    }

    final startIndex = matches[index].start;
    final endIndex = index + 1 < matches.length ? matches[index + 1].start : html.length;
    final fragment = html.substring(startIndex, endIndex);
    final year = _parseAnimeScheduleYearFragment(fragment, yearTitle);
    if (year.periods.isNotEmpty) {
      years.add(year);
    }
  }

  if (years.isEmpty) {
    throw const FormatException('未解析到任何年份数据');
  }

  return AnimeScheduleCollection(years: years);
}

AnimeScheduleYear parseAnimeScheduleYear(
  String html, {
  String yearTitle = '2026年新番',
}) {
  final collection = parseAnimeScheduleCollection(html);
  return collection.years.firstWhere(
    (year) => year.title == yearTitle,
    orElse: () => throw FormatException('未找到目标年份：$yearTitle'),
  );
}

AnimeScheduleYear _parseAnimeScheduleYearFragment(String fragment, String yearTitle) {
  final document = html_parser.parseFragment(fragment);
  final orderedElements = document.querySelectorAll(
    'h3, div.content_f_Uak, div.moduleTable_anKlO',
  );

  final periods = <AnimeSchedulePeriod>[];
  AnimeSchedulePeriod? currentPeriod;
  String? currentGroupTitle;

  for (final element in orderedElements) {
    if (element.localName == 'h3') {
      currentPeriod = AnimeSchedulePeriod(
        title: _normalizeText(element.text),
        groups: <AnimeScheduleGroup>[],
      );
      periods.add(currentPeriod);
      currentGroupTitle = null;
      continue;
    }

    if (element.classes.contains('content_f_Uak')) {
      final groupTitle = _normalizeText(element.text);
      if (groupTitle.isNotEmpty && currentPeriod != null) {
        currentGroupTitle = groupTitle;
      }
      continue;
    }

    if (element.classes.contains('moduleTable_anKlO') &&
        currentPeriod != null &&
        currentGroupTitle != null) {
      final table = element.querySelector('table');
      if (table == null) {
        continue;
      }

      final parsedTable = _parseTable(table, currentGroupTitle);
      if (parsedTable != null) {
        currentPeriod.groups.add(parsedTable);
      }
    }
  }

  return AnimeScheduleYear(
    title: yearTitle,
    periods: periods.where((period) => period.groups.isNotEmpty).toList(),
  );
}

AnimeScheduleGroup? _parseTable(Element table, String title) {
  final rows = table.querySelectorAll('tr');
  if (rows.isEmpty) {
    return null;
  }

  final headerCells = rows.first.querySelectorAll('th, td');
  final columns = headerCells.map((cell) => _normalizeText(cell.text)).toList();
  if (columns.isEmpty) {
    return null;
  }

  final entries = <AnimeScheduleEntry>[];
  for (final row in rows.skip(1)) {
    final cells = row.querySelectorAll('td, th');
    if (cells.isEmpty) {
      continue;
    }

    final values = cells.map(_extractCellText).toList();
    if (values.every((value) => value.isEmpty)) {
      continue;
    }

    entries.add(AnimeScheduleEntry(values: values));
  }

  if (entries.isEmpty) {
    return null;
  }

  return AnimeScheduleGroup(
    title: title,
    columns: columns,
    entries: entries,
  );
}

String _extractCellText(Element cell) {
  final textParts = cell
      .querySelectorAll('.J-lemma-content-lemma-text')
      .map((node) => _normalizeText(node.text))
      .where((text) => text.isNotEmpty)
      .toList();

  if (textParts.isNotEmpty) {
    return _joinReadableText(textParts);
  }

  return _normalizeText(cell.text);
}

String _joinReadableText(List<String> parts) {
  final buffer = StringBuffer();
  for (final part in parts) {
    if (buffer.isEmpty) {
      buffer.write(part);
      continue;
    }

    final previous = buffer.toString();
    final needsSpace = _needsSpaceBetween(previous, part);
    if (needsSpace) {
      buffer.write(' ');
    }
    buffer.write(part);
  }
  return _normalizeText(buffer.toString());
}

bool _needsSpaceBetween(String previous, String next) {
  if (previous.isEmpty || next.isEmpty) {
    return false;
  }

  const noLeadingSpaceChars = '），。！？、）》】」】';
  const noTrailingSpaceChars = '（《【「';
  if (noLeadingSpaceChars.contains(next[0]) ||
      noTrailingSpaceChars.contains(previous[previous.length - 1])) {
    return false;
  }

  final previousEndsAscii = RegExp(r'[A-Za-z0-9]$').hasMatch(previous);
  final nextStartsAscii = RegExp(r'^[A-Za-z0-9]').hasMatch(next);
  return previousEndsAscii && nextStartsAscii;
}

String _normalizeText(String value) {
  return value
      .replaceAll('\u00a0', ' ')
      .replaceAll(RegExp(r'\[[0-9]+\]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
