import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/acg_rss_detail_service.dart';
import 'acg_rss_detail_parser.dart';
import 'acg_rss_parser.dart';

typedef AcgRssDetailLoader =
    Future<AcgRssDetail> Function({
      required String detailUrl,
    });

class AcgRssDetailPage extends StatefulWidget {
  const AcgRssDetailPage({
    super.key,
    required this.topic,
    this.loader = _fetchDetailFromNetwork,
  });

  final AcgRssTopic topic;
  final AcgRssDetailLoader loader;

  static Future<AcgRssDetail> _fetchDetailFromNetwork({
    required String detailUrl,
  }) =>
      const AcgRssDetailService().fetchDetail(detailUrl: detailUrl);

  @override
  State<AcgRssDetailPage> createState() => _AcgRssDetailPageState();
}

class _AcgRssDetailPageState extends State<AcgRssDetailPage> {
  AcgRssDetail? _detail;
  String? _errorMessage;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDetail();
    });
  }

  Future<void> _loadDetail() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final detail = await widget.loader(detailUrl: widget.topic.detailUrl);
      if (!mounted) {
        return;
      }
      setState(() {
        _detail = detail;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '获取详情失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pageTitle = widget.topic.animeName.isEmpty
        ? widget.topic.rawTitle
        : widget.topic.animeName;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          pageTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFFB42318),
            ),
          ),
        ),
      );
    }

    final detail = _detail;
    if (detail == null) {
      return const Center(
        child: Text(
          '没有解析到详情数据',
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF667085),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE4E7EC)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                detail.title.isEmpty ? widget.topic.rawTitle : detail.title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF101828),
                  height: 1.45,
                ),
              ),
              if (detail.postedAt.isNotEmpty || detail.size.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (detail.postedAt.isNotEmpty)
                      _MetaChip(label: '发布时间 ${detail.postedAt}'),
                    if (detail.size.isNotEmpty) _MetaChip(label: '大小 ${detail.size}'),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '下载链接',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Color(0xFF101828),
          ),
        ),
        const SizedBox(height: 10),
        if (detail.links.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE4E7EC)),
            ),
            child: const Text(
              '没有解析到可用下载链接',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF667085),
              ),
            ),
          )
        else
          ...detail.links.map(_buildLinkCard),
      ],
    );
  }

  Widget _buildLinkCard(AcgRssDownloadLink link) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            link.label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101828),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _previewUrl(link.url),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: Color(0xFF475467),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => _copyLink(link),
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('复制'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _copyLink(AcgRssDownloadLink link) async {
    await Clipboard.setData(ClipboardData(text: link.url));
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制${link.label}'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _previewUrl(String url) {
    final normalized = url.trim();
    if (normalized.length <= 90) {
      return normalized;
    }

    const headLength = 42;
    const tailLength = 28;
    return '${normalized.substring(0, headLength)}...${normalized.substring(normalized.length - tailLength)}';
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF344054),
        ),
      ),
    );
  }
}
