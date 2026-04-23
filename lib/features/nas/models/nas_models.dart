class SynologyApiException implements Exception {
  const SynologyApiException(this.message, {this.code});

  final String message;
  final int? code;

  @override
  String toString() => code == null ? message : '$message (code: $code)';
}

class NasFileEntry {
  const NasFileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.sizeLabel,
    this.modifiedAtLabel,
  });

  final String name;
  final String path;
  final bool isDirectory;
  final String? sizeLabel;
  final String? modifiedAtLabel;

  factory NasFileEntry.fromJson(Map<String, dynamic> json) {
    final additional = json['additional'];
    final timeInfo =
        additional is Map<String, dynamic> ? additional['time'] : null;

    return NasFileEntry(
      name: (json['name'] ?? '').toString(),
      path: (json['path'] ?? '').toString(),
      isDirectory: json['isdir'] == true,
      sizeLabel: formatSizeLabel(additional),
      modifiedAtLabel: formatModifiedLabel(timeInfo),
    );
  }

  static String? formatSizeLabel(dynamic additional) {
    if (additional is! Map<String, dynamic>) {
      return null;
    }

    final size = additional['size'];
    if (size is! num || size <= 0) {
      return null;
    }

    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = size.toDouble();
    var index = 0;
    while (value >= 1024 && index < units.length - 1) {
      value /= 1024;
      index++;
    }

    final text =
        value >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
    return '$text ${units[index]}';
  }

  static String? formatModifiedLabel(dynamic timeInfo) {
    if (timeInfo is! Map<String, dynamic>) {
      return null;
    }

    final mtime = timeInfo['mtime'];
    if (mtime is! num || mtime <= 0) {
      return null;
    }

    final time = DateTime.fromMillisecondsSinceEpoch(
      (mtime * 1000).toInt(),
    ).toLocal();

    String twoDigits(int value) => value.toString().padLeft(2, '0');

    return '${time.year}-${twoDigits(time.month)}-${twoDigits(time.day)} '
        '${twoDigits(time.hour)}:${twoDigits(time.minute)}';
  }
}

class NasDownloadTask {
  const NasDownloadTask({
    required this.id,
    required this.title,
    required this.status,
    required this.type,
    this.sizeLabel,
    this.downloadedLabel,
    this.speedLabel,
    this.destination,
    this.username,
  });

  final String id;
  final String title;
  final String status;
  final String type;
  final String? sizeLabel;
  final String? downloadedLabel;
  final String? speedLabel;
  final String? destination;
  final String? username;

  factory NasDownloadTask.fromJson(Map<String, dynamic> json) {
    final additional =
        json['additional'] is Map<String, dynamic>
            ? json['additional'] as Map<String, dynamic>
            : const <String, dynamic>{};
    final detail =
        additional['detail'] is Map<String, dynamic>
            ? additional['detail'] as Map<String, dynamic>
            : const <String, dynamic>{};
    final transfer =
        additional['transfer'] is Map<String, dynamic>
            ? additional['transfer'] as Map<String, dynamic>
            : const <String, dynamic>{};

    final totalSize =
        json['size'] is num ? (json['size'] as num).toDouble() : null;
    final sizeDownloaded =
        transfer['size_downloaded'] is num
            ? (transfer['size_downloaded'] as num).toDouble()
            : null;
    final speedDownload =
        transfer['speed_download'] is num
            ? (transfer['speed_download'] as num).toDouble()
            : null;

    return NasDownloadTask(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '未命名任务').toString(),
      status: (json['status'] ?? 'unknown').toString(),
      type: (json['type'] ?? 'unknown').toString(),
      sizeLabel: _formatBytes(totalSize),
      downloadedLabel: _formatBytes(sizeDownloaded),
      speedLabel: speedDownload == null ? null : '${_formatBytes(speedDownload)}/s',
      destination: detail['destination']?.toString(),
      username: json['username']?.toString(),
    );
  }

  String get statusLabel {
    switch (status) {
      case 'downloading':
        return '下载中';
      case 'paused':
        return '已暂停';
      case 'waiting':
        return '等待中';
      case 'finishing':
        return '整理中';
      case 'seeding':
        return '做种中';
      case 'finished':
        return '已完成';
      case 'hash_checking':
        return '校验中';
      case 'extracting':
        return '解压中';
      case 'error':
        return '失败';
      default:
        return status;
    }
  }

  static String? _formatBytes(double? size) {
    if (size == null || size <= 0) {
      return null;
    }
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = size;
    var index = 0;
    while (value >= 1024 && index < units.length - 1) {
      value /= 1024;
      index++;
    }
    final text =
        value >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
    return '$text ${units[index]}';
  }
}

enum NasDownloadTaskFilter {
  all('全部'),
  downloading('下载中'),
  completed('已完成');

  const NasDownloadTaskFilter(this.label);

  final String label;
}
