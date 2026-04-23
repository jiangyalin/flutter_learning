import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/acg_rss_detail_service.dart';
import '../services/acg_rss_service.dart';
import 'acg_rss_detail_page.dart';
import 'acg_rss_detail_parser.dart';
import 'acg_rss_parser.dart';

typedef AcgRssLoader = Future<List<AcgRssTopic>> Function({
  required int page,
  required String keyword,
});
typedef AcgRssDetailPageBuilder = Widget Function(AcgRssTopic topic);
typedef AcgRssQuickDetailLoader = Future<AcgRssDetail> Function({
  required String detailUrl,
});
typedef AcgRssClipboardSetter = Future<void> Function(String text);

class AcgRssPage extends StatefulWidget {
  const AcgRssPage({
    super.key,
    this.loader = _fetchTopicsFromNetwork,
    this.initialKeyword = '',
    this.detailPageBuilder = _buildDetailPage,
    this.detailLoader = _fetchDetailFromNetwork,
    this.clipboardSetter = _copyToClipboard,
  });

  final AcgRssLoader loader;
  final String initialKeyword;
  final AcgRssDetailPageBuilder detailPageBuilder;
  final AcgRssQuickDetailLoader detailLoader;
  final AcgRssClipboardSetter clipboardSetter;

  static Future<List<AcgRssTopic>> _fetchTopicsFromNetwork({
    required int page,
    required String keyword,
  }) =>
      const AcgRssService().fetchTopics(page: page, keyword: keyword);

  static Widget _buildDetailPage(AcgRssTopic topic) {
    return AcgRssDetailPage(topic: topic);
  }

  static Future<AcgRssDetail> _fetchDetailFromNetwork({
    required String detailUrl,
  }) =>
      const AcgRssDetailService().fetchDetail(detailUrl: detailUrl);

  static Future<void> _copyToClipboard(String text) {
    return Clipboard.setData(ClipboardData(text: text));
  }

  @override
  State<AcgRssPage> createState() => _AcgRssPageState();
}

class _AcgRssPageState extends State<AcgRssPage> {
  static const _scrollThreshold = 240.0;

  final ScrollController _scrollController = ScrollController();
  late final TextEditingController _keywordController;

  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _errorMessage;
  List<AcgRssTopic> _topics = const [];
  int _currentPage = 0;
  String _activeKeyword = '';
  final Set<String> _quickCopyingTopicKeys = {};

  @override
  void initState() {
    super.initState();
    _activeKeyword = widget.initialKeyword.trim();
    _keywordController = TextEditingController(text: _activeKeyword);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _fetchTopics(keyword: widget.initialKeyword);
    });
  }

  @override
  void didUpdateWidget(covariant AcgRssPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextKeyword = widget.initialKeyword.trim();
    if (nextKeyword == oldWidget.initialKeyword.trim() ||
        nextKeyword == _activeKeyword) {
      return;
    }

    _keywordController.text = nextKeyword;
    _fetchTopics(keyword: nextKeyword);
  }

  @override
  void dispose() {
    _keywordController.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  Future<void> _fetchTopics({String? keyword}) async {
    final nextKeyword = (keyword ?? _keywordController.text).trim();
    if (nextKeyword != _activeKeyword) {
      if (!mounted) {
        return;
      }
      setState(() {
        _activeKeyword = nextKeyword;
      });
    }
    await _fetchPage(reset: true);
  }

  Future<void> _fetchNextPage() async {
    if (_isLoading || _isLoadingMore || !_hasMore) {
      return;
    }
    await _fetchPage(page: _currentPage + 1);
  }

  Future<void> _fetchPage({bool reset = false, int? page}) async {
    final targetPage = reset ? 1 : (page ?? _currentPage + 1);

    setState(() {
      if (reset) {
        _isLoading = true;
        _topics = const [];
        _currentPage = 0;
        _hasMore = true;
        _errorMessage = null;
      } else {
        _isLoadingMore = true;
      }
    });

    try {
      final topics = await widget.loader(
        page: targetPage,
        keyword: _activeKeyword,
      );
      if (!mounted) {
        return;
      }
      final mergedTopics = reset ? topics : _mergeTopics(_topics, topics);

      setState(() {
        _topics = mergedTopics;
        _currentPage = targetPage;
        _hasMore = topics.isNotEmpty;
        _errorMessage = mergedTopics.isEmpty
            ? (_activeKeyword.isEmpty ? '没有解析到表格数据' : '没有找到相关结果')
            : null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '获取失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          if (reset) {
            _isLoading = false;
          } else {
            _isLoadingMore = false;
          }
        });
      }
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }

    final position = _scrollController.position;
    final shouldLoadMore =
        position.maxScrollExtent - position.pixels <= _scrollThreshold;

    if (shouldLoadMore) {
      _fetchNextPage();
    }
  }

  void _submitSearch() {
    FocusScope.of(context).unfocus();
    final nextKeyword = _keywordController.text.trim();
    if (nextKeyword == _activeKeyword && _topics.isNotEmpty) {
      return;
    }

    setState(() {
      _activeKeyword = nextKeyword;
    });
    _fetchTopics(keyword: nextKeyword);
  }

  void _clearSearch() {
    _keywordController.clear();
    if (_activeKeyword.isEmpty) {
      return;
    }

    setState(() {
      _activeKeyword = '';
    });
    _fetchTopics(keyword: '');
  }

  List<AcgRssTopic> _mergeTopics(
    List<AcgRssTopic> existing,
    List<AcgRssTopic> incoming,
  ) {
    final merged = <AcgRssTopic>[...existing];
    final knownKeys = existing.map(_topicKey).toSet();

    for (final topic in incoming) {
      final key = _topicKey(topic);
      if (knownKeys.add(key)) {
        merged.add(topic);
      }
    }

    return merged;
  }

  String _topicKey(AcgRssTopic topic) {
    if (topic.detailUrl.isNotEmpty) {
      return topic.detailUrl;
    }
    return '${topic.postedAt}-${topic.rawTitle}-${topic.publisher}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ACG RSS'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: TextField(
              controller: _keywordController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _submitSearch(),
              decoration: InputDecoration(
                hintText: '输入关键字搜索',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_keywordController.text.isNotEmpty)
                      IconButton(
                        tooltip: '清空',
                        onPressed: _clearSearch,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    IconButton(
                      tooltip: '搜索',
                      onPressed: _isLoading ? null : _submitSearch,
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
                  ],
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
              onChanged: (_) {
                setState(() {});
              },
            ),
          ),
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading && _topics.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _topics.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFB42318),
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    if (_topics.isEmpty) {
      return Center(
        child: Text(
          _activeKeyword.isEmpty ? '正在准备内容…' : '没有找到相关结果',
          style: const TextStyle(
            color: Color(0xFF667085),
            fontSize: 14,
          ),
        ),
      );
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: _topics.length + 1,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == _topics.length) {
          return _buildLoadMoreFooter();
        }

        final topic = _topics[index];
        final topicKey = _topicKey(topic);
        return _TopicCard(
          topic: topic,
          isQuickCopying: _quickCopyingTopicKeys.contains(topicKey),
          onTap: () => _openDetailPage(topic),
          onQuickCopy: () => _quickCopyMagnet(topic),
        );
      },
    );
  }

  void _openDetailPage(AcgRssTopic topic) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => widget.detailPageBuilder(topic),
      ),
    );
  }

  Future<void> _quickCopyMagnet(AcgRssTopic topic) async {
    final topicKey = _topicKey(topic);
    if (_quickCopyingTopicKeys.contains(topicKey)) {
      return;
    }

    setState(() {
      _quickCopyingTopicKeys.add(topicKey);
    });

    try {
      final detail = await widget.detailLoader(detailUrl: topic.detailUrl);
      final magnet = _findPrimaryMagnetLink(detail.links);
      if (magnet == null) {
        throw Exception('没有解析到 Magnet连接');
      }

      await widget.clipboardSetter(magnet.url);
      if (!mounted) {
        return;
      }
      _showSnackBar('已复制${magnet.label}');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar('快速取链失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _quickCopyingTopicKeys.remove(topicKey);
        });
      }
    }
  }

  AcgRssDownloadLink? _findPrimaryMagnetLink(List<AcgRssDownloadLink> links) {
    for (final link in links) {
      if (link.url.startsWith('magnet:') &&
          (link.label == 'Magnet連接' || link.label == 'Magnet连接')) {
        return link;
      }
    }

    for (final link in links) {
      if (link.url.startsWith('magnet:') &&
          !link.label.toLowerCase().contains('typeii')) {
        return link;
      }
    }

    for (final link in links) {
      if (link.url.startsWith('magnet:')) {
        return link;
      }
    }

    return null;
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Widget _buildLoadMoreFooter() {
    if (_isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Text(
            '没有更多数据了',
            style: TextStyle(
              color: Color(0xFF98A2B3),
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    return const SizedBox(height: 1);
  }
}

class _TopicCard extends StatefulWidget {
  const _TopicCard({
    required this.topic,
    required this.isQuickCopying,
    required this.onTap,
    required this.onQuickCopy,
  });

  final AcgRssTopic topic;
  final bool isQuickCopying;
  final VoidCallback onTap;
  final VoidCallback onQuickCopy;

  @override
  State<_TopicCard> createState() => _TopicCardState();
}

class _TopicCardState extends State<_TopicCard> {
  bool _showRawTitle = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE4E7EC)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.topic.animeName.isEmpty
                    ? widget.topic.rawTitle
                    : widget.topic.animeName,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF101828),
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _showRawTitle = !_showRawTitle;
                    });
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 0,
                      vertical: 0,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  icon: Icon(
                    _showRawTitle
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    size: 14,
                  ),
                  label: Text(_showRawTitle ? '隐藏原始名' : '查看原始名'),
                ),
              ),
              if (_showRawTitle) ...[
                const SizedBox(height: 3),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE4E7EC)),
                  ),
                  child: Text(
                    widget.topic.rawTitle,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      color: Color(0xFF475467),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (widget.topic.episode.isNotEmpty)
                    _InfoChip(label: '集数 ${widget.topic.episode}'),
                  if (widget.topic.resolution.isNotEmpty)
                    _InfoChip(label: '分辨率 ${widget.topic.resolution}'),
                  if (widget.topic.subtitleLanguage.isNotEmpty)
                    _InfoChip(label: '字幕 ${widget.topic.subtitleLanguage}'),
                  if (widget.topic.size.isNotEmpty)
                    _InfoChip(label: '大小 ${widget.topic.size}'),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '下载次数：${widget.topic.downloads}  完成次数：${widget.topic.completed}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF667085),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    OutlinedButton.icon(
                      onPressed:
                          widget.isQuickCopying ? null : widget.onQuickCopy,
                      icon: widget.isQuickCopying
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.content_copy_rounded, size: 16),
                      label: const Text('快速取链'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: widget.onTap,
                      icon: const Icon(Icons.link_rounded, size: 16),
                      label: const Text('取链'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFF344054),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
