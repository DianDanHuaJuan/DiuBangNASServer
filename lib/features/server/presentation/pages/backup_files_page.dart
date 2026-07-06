import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import '../../../../app/di/service_locator.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/media/media_kit_bootstrap.dart';
import '../../../../core/storage/backup_catalog_service.dart';
import '../../../../core/storage/file_index_service.dart';
import '../../../../core/storage/thumbnail_service.dart';

/// 将备份目录下的 WebDAV 风格相对路径解析为本地绝对路径。
String resolveBackupFileLocalPath(String relativePath) {
  final catalog = ServiceLocator.backupCatalogService;
  if (catalog != null) {
    return catalog.resolveLocalPath(relativePath);
  }
  final root = ServiceLocator.storageRootPath.trim();
  final segments = relativePath
      .split('/')
      .where((segment) => segment.isNotEmpty);
  return p.joinAll([root, ...segments]);
}

class BackupFilesPage extends StatefulWidget {
  const BackupFilesPage({super.key});

  @override
  State<BackupFilesPage> createState() => _BackupFilesPageState();
}

class _BackupFilesPageState extends State<BackupFilesPage>
    with AutomaticKeepAliveClientMixin {
  static const int _pageSize = 48;

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _reloadInFlight = false;
  String? _errorMessage;
  String _selectedCategory = 'photo';
  List<BackupFileRecord> _files = const [];
  bool _hasMore = false;
  String? _nextCursor;

  final List<_CategoryOption> _categories = const [
    _CategoryOption(key: 'photo', label: '图片'),
    _CategoryOption(key: 'video', label: '视频'),
    _CategoryOption(key: 'document', label: '文档'),
    _CategoryOption(key: 'other', label: '其他'),
  ];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    ServiceLocator.localFileServicesReady.addListener(_onLocalFileServicesReady);
    unawaited(_reload());
  }

  @override
  void dispose() {
    ServiceLocator.localFileServicesReady.removeListener(
      _onLocalFileServicesReady,
    );
    super.dispose();
  }

  void _onLocalFileServicesReady() {
    if (!mounted || !ServiceLocator.localFileServicesReady.value) {
      return;
    }
    if (_reloadInFlight || _isLoading) {
      return;
    }
    if (ServiceLocator.fileIndexService == null) {
      return;
    }
    if (_errorMessage == null && _files.isNotEmpty) {
      return;
    }
    unawaited(_reload());
  }

  Future<void> _reload() async {
    if (_reloadInFlight) {
      return;
    }

    _reloadInFlight = true;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      if (ServiceLocator.backupCatalogService == null) {
        await ServiceLocator.ensureMinimalCoreServices();
      }

      final indexService = ServiceLocator.fileIndexService;
      if (indexService == null) {
        if (!mounted) return;
        final storagePath = ServiceLocator.storageRootPath.trim();
        setState(() {
          _files = const [];
          _hasMore = false;
          _nextCursor = null;
          _isLoading = false;
          _errorMessage = storagePath.isEmpty
              ? '请先在设置中配置存储路径。'
              : '无法访问备份目录，请检查存储路径设置。';
        });
        return;
      }

      await _logReloadDiagnostics(
        indexService: indexService,
        category: _selectedCategory,
      );

      final page = await _loadFilePage(
        indexService: indexService,
        category: _selectedCategory,
      );
      if (!mounted) return;
      setState(() {
        _files = page.items;
        _hasMore = page.hasMore;
        _nextCursor = page.nextCursor;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '加载失败：$error';
        _isLoading = false;
      });
    } finally {
      _reloadInFlight = false;
    }
  }

  Future<void> _loadMore() async {
    final indexService = ServiceLocator.fileIndexService;
    final cursor = _nextCursor;
    if (indexService == null ||
        _isLoading ||
        _isLoadingMore ||
        !_hasMore ||
        cursor == null) {
      return;
    }

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final page = await _loadFilePage(
        indexService: indexService,
        cursor: cursor,
        category: _selectedCategory,
      );
      if (!mounted) return;
      setState(() {
        _files = [..._files, ...page.items];
        _hasMore = page.hasMore;
        _nextCursor = page.nextCursor;
        _isLoadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '继续加载失败：$error';
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _selectCategory(String category) async {
    if (_selectedCategory == category) return;
    setState(() {
      _selectedCategory = category;
      _files = const [];
      _nextCursor = null;
      _hasMore = false;
    });
    await _reload();
  }

  Future<BackupFilePage> _loadFilePage({
    required FileIndexService indexService,
    String? cursor,
    required String category,
  }) async {
    final indexed = await indexService.listFiles(
      cursor: cursor,
      limit: _pageSize,
      category: category,
    );
    return BackupFilePage(
      items: indexed.items.map(_recordFromIndexed).toList(growable: false),
      hasMore: indexed.hasMore,
      nextCursor: indexed.nextCursor,
    );
  }

  BackupFileRecord _recordFromIndexed(IndexedFileEntry entry) {
    return BackupFileRecord(
      relativePath: entry.path,
      name: entry.name,
      extension: p.extension(entry.name).toLowerCase(),
      category: entry.category,
      sizeBytes: entry.size,
      modifiedAt: entry.modifiedAt,
      updatedAt: entry.modifiedAt,
      referenceCount: 1,
      deviceCount: 0,
      latestDeviceLabel: '',
    );
  }

  Future<void> _logReloadDiagnostics({
    required FileIndexService indexService,
    required String category,
  }) async {
    final root = ServiceLocator.storageRootPath.trim();
    debugPrint(
      '[BackupFilesPage] reload category=$category storageRoot=$root',
    );

    final catalog = ServiceLocator.backupCatalogService;
    if (catalog != null) {
      try {
        final overview = await catalog.fetchOverview();
        debugPrint(
          '[BackupFilesPage] backup_catalog distinctFiles='
          '${overview.totalStoredFiles} records=${overview.totalRecords}',
        );
        final catalogPage = await catalog.listBackupFiles(
          limit: 3,
          category: category,
        );
        debugPrint(
          '[BackupFilesPage] backup_catalog page(${category}) '
          'items=${catalogPage.items.length} hasMore=${catalogPage.hasMore}',
        );
      } catch (error, stack) {
        debugPrint('[BackupFilesPage] backup_catalog diagnostic failed: $error');
        debugPrint('$stack');
      }
    } else {
      debugPrint('[BackupFilesPage] backup_catalog service=null');
    }

    try {
      final indexPage = await indexService.listFiles(
        limit: 3,
        category: category,
      );
      debugPrint(
        '[BackupFilesPage] file_index page($category) '
        'items=${indexPage.items.length} hasMore=${indexPage.hasMore} '
        'sample=${indexPage.items.map((e) => e.path).take(2).join(", ")}',
      );
    } catch (error, stack) {
      debugPrint('[BackupFilesPage] file_index diagnostic failed: $error');
      debugPrint('$stack');
    }
  }

  Future<void> _openPreview(BackupFileRecord record) async {
    final localPath = resolveBackupFileLocalPath(record.relativePath);
    if (!await File(localPath).exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文件不存在，已无法预览。')),
      );
      return;
    }

    if (!mounted) return;

    final mediaItems = _files
        .where((f) => f.category == 'photo' || f.category == 'video')
        .toList();
    final initialIndex = mediaItems.indexWhere(
      (item) => item.relativePath == record.relativePath,
    );
    if (initialIndex < 0) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MediaPreviewPage(
          items: mediaItems,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = constraints.maxWidth > 1280
            ? 1280.0
            : constraints.maxWidth;
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 20),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: contentWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 16),
                  _buildCategoryBar(),
                  const SizedBox(height: 20),
                  if (_isLoading)
                    _buildLoadingState()
                  else if (_errorMessage != null)
                    _buildErrorState(_errorMessage!)
                  else
                    _buildFilesGrid(contentWidth),
                  if (_hasMore || _isLoadingMore) ...[
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.center,
                      child: FilledButton.tonalIcon(
                        onPressed: _isLoadingMore ? null : _loadMore,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.accentColor,
                          foregroundColor: Colors.white,
                        ),
                        icon: _isLoadingMore
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.expand_more_rounded),
                        label: Text(_isLoadingMore ? '加载中...' : '加载更多'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '文件',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.lightCardForeground,
                ),
              ),
              SizedBox(height: 6),
              Text(
                '浏览备份目录中的资源',
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.lightSecondaryText,
                ),
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: _isLoading ? null : _reload,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('刷新'),
        ),
      ],
    );
  }

  Widget _buildCategoryBar() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.lightDivider, width: 1),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _categories.length; i++) ...[
            if (i > 0)
              Container(width: 1, color: AppTheme.lightDivider),
            Expanded(
              child: _buildCategoryItem(
                option: _categories[i],
                index: i,
                total: _categories.length,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCategoryItem({
    required _CategoryOption option,
    required int index,
    required int total,
  }) {
    final selected = _selectedCategory == option.key;
    final isFirst = index == 0;
    final isLast = index == total - 1;

    return GestureDetector(
      onTap: () => _selectCategory(option.key),
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFCFE1FF)
              : Colors.transparent,
          borderRadius: BorderRadius.horizontal(
            left: isFirst ? const Radius.circular(7) : Radius.zero,
            right: isLast ? const Radius.circular(7) : Radius.zero,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          option.label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: selected
                ? AppTheme.accentColor
                : AppTheme.lightCardForeground,
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      width: double.infinity,
      decoration: _moduleDecoration(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: const Column(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          SizedBox(height: 16),
          Text(
            '正在准备备份目录...',
            style: TextStyle(fontSize: 14, color: AppTheme.lightSecondaryText),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return _buildStateCard(
      icon: Icons.folder_off_outlined,
      title: '无法加载备份目录',
      message: message,
      action: FilledButton(onPressed: _reload, child: const Text('重试')),
    );
  }

  Widget _buildStateCard({
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) {
    return Container(
      width: double.infinity,
      decoration: _moduleDecoration(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        children: [
          Icon(icon, size: 30, color: AppTheme.lightSecondaryText),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppTheme.lightCardForeground,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: AppTheme.lightSecondaryText,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 18), action],
        ],
      ),
    );
  }

  Widget _buildFilesGrid(double contentWidth) {
    if (_files.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 48),
        decoration: BoxDecoration(
          color: AppTheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Column(
          children: [
            Icon(
              Icons.folder_open_rounded,
              size: 30,
              color: AppTheme.lightSecondaryText,
            ),
            SizedBox(height: 12),
            Text(
              '当前分类下没有文件',
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.lightSecondaryText,
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 1200
            ? 6
            : constraints.maxWidth >= 960
            ? 5
            : constraints.maxWidth >= 720
            ? 4
            : constraints.maxWidth >= 480
            ? 3
            : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _files.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.0,
          ),
          itemBuilder: (context, index) {
            final record = _files[index];
            return _buildGridItem(record);
          },
        );
      },
    );
  }

  Widget _buildGridItem(BackupFileRecord record) {
    final isMedia = record.category == 'photo' || record.category == 'video';

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: isMedia ? () => _openPreview(record) : null,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: AppTheme.surfaceContainerLow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (isMedia)
              _BackupThumbnail(record: record)
            else
              _buildFileIcon(record.category),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 20, 10, 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.0),
                      Colors.black.withValues(alpha: 0.55),
                    ],
                  ),
                ),
                child: Text(
                  record.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileIcon(String category) {
    final icon = switch (category) {
      'document' => Icons.description_outlined,
      'audio' => Icons.audiotrack_rounded,
      _ => Icons.insert_drive_file_outlined,
    };
    return Center(
      child: Icon(
        icon,
        size: 48,
        color: AppTheme.lightSecondaryText,
      ),
    );
  }

  BoxDecoration _moduleDecoration() {
    return BoxDecoration(
      color: AppTheme.lightCard,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppTheme.lightDivider, width: 1),
      boxShadow: const [
        BoxShadow(
          color: Color(0x08000000),
          blurRadius: 3,
          offset: Offset(0, 1),
        ),
      ],
    );
  }
}

class _BackupThumbnail extends StatefulWidget {
  const _BackupThumbnail({required this.record});

  final BackupFileRecord record;

  @override
  State<_BackupThumbnail> createState() => _BackupThumbnailState();
}

class _BackupThumbnailState extends State<_BackupThumbnail> {
  Future<String?>? _thumbPathFuture;

  @override
  void initState() {
    super.initState();
    _thumbPathFuture = _loadThumbPath();
  }

  @override
  void didUpdateWidget(covariant _BackupThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.record.relativePath != widget.record.relativePath) {
      _thumbPathFuture = _loadThumbPath();
    }
  }

  Future<String?> _loadThumbPath() async {
    final thumbnailService = ServiceLocator.thumbnailService;
    if (thumbnailService == null) return null;

    final category = widget.record.category;
    if (category != 'photo' && category != 'video') return null;

    return thumbnailService.getThumbnailPath(
      '/fs${widget.record.relativePath}',
      ThumbnailType.grid,
    );
  }

  @override
  Widget build(BuildContext context) {
    final category = widget.record.category;
    final isVideo = category == 'video';

    return FutureBuilder<String?>(
      future: _thumbPathFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            color: AppTheme.surfaceContainerLow,
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final thumbPath = snapshot.data;
        String? imagePath;
        if (thumbPath != null) {
          imagePath = thumbPath;
        } else if (category == 'photo') {
          imagePath = resolveBackupFileLocalPath(widget.record.relativePath);
        }

        if (imagePath == null) {
          return _buildFallback(category);
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(imagePath),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => _buildFallback(category),
            ),
            if (isVideo)
              Container(
                color: Colors.black.withValues(alpha: 0.12),
                child: const Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0xAA000000),
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildFallback(String category) {
    final icon = switch (category) {
      'video' => Icons.movie_outlined,
      _ => Icons.image_outlined,
    };
    return Container(
      color: AppTheme.surfaceContainerLow,
      child: Center(
        child: Icon(
          icon,
          size: 40,
          color: AppTheme.lightSecondaryText,
        ),
      ),
    );
  }
}

// MediaPreviewPage — 支持左右滑动/箭头/键盘切换媒体文件

class _PreviousPreviewIntent extends Intent {
  const _PreviousPreviewIntent();
}

class _NextPreviewIntent extends Intent {
  const _NextPreviewIntent();
}

class MediaPreviewPage extends StatefulWidget {
  const MediaPreviewPage({
    super.key,
    required this.items,
    required this.initialIndex,
  });

  final List<BackupFileRecord> items;
  final int initialIndex;

  @override
  State<MediaPreviewPage> createState() => _MediaPreviewPageState();
}

class _MediaPreviewPageState extends State<MediaPreviewPage> {
  late final PageController _pageController;
  late int _currentIndex;
  bool _imageZoomed = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  BackupFileRecord get _currentItem => widget.items[_currentIndex];
  int get _total => widget.items.length;
  bool get _canGoPrevious => _currentIndex > 0;
  bool get _canGoNext => _currentIndex < _total - 1;
  bool get _showNavControls => _total > 1 && !_imageZoomed;

  void _goToPrevious() {
    if (!_canGoPrevious) return;
    unawaited(
      _pageController.previousPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      ),
    );
  }

  void _goToNext() {
    if (!_canGoNext) return;
    unawaited(
      _pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      ),
    );
  }

  void _handleImageZoomChanged(bool zoomed) {
    if (!mounted || _imageZoomed == zoomed) return;
    setState(() => _imageZoomed = zoomed);
  }

  Widget _buildNavArrow({
    required IconData icon,
    required VoidCallback? onPressed,
    required Alignment alignment,
    required String tooltip,
  }) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Material(
          color: Colors.black.withValues(alpha: 0.45),
          shape: const CircleBorder(),
          child: IconButton(
            icon: Icon(icon, color: Colors.white, size: 32),
            onPressed: onPressed,
            tooltip: tooltip,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.arrowLeft): _PreviousPreviewIntent(),
          SingleActivator(LogicalKeyboardKey.arrowRight): _NextPreviewIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _PreviousPreviewIntent: CallbackAction<_PreviousPreviewIntent>(
              onInvoke: (_) {
                _goToPrevious();
                return null;
              },
            ),
            _NextPreviewIntent: CallbackAction<_NextPreviewIntent>(
              onInvoke: (_) {
                _goToNext();
                return null;
              },
            ),
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: Text(
                _currentItem.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                if (_total > 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Center(
                      child: Text(
                        '${_currentIndex + 1} / $_total',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: '关闭',
                ),
              ],
            ),
            body: Stack(
              fit: StackFit.expand,
              children: [
                PageView.builder(
                  controller: _pageController,
                  itemCount: _total,
                  onPageChanged: (index) {
                    setState(() {
                      _currentIndex = index;
                      _imageZoomed = false;
                    });
                  },
                  itemBuilder: (context, index) {
                    final item = widget.items[index];
                    final path = resolveBackupFileLocalPath(item.relativePath);
                    if (item.category == 'video') {
                      return _VideoPreviewContent(filePath: path);
                    }
                    return _ImagePreviewContent(
                      filePath: path,
                      onZoomChanged: index == _currentIndex
                          ? _handleImageZoomChanged
                          : null,
                    );
                  },
                ),
                if (_showNavControls) ...[
                  _buildNavArrow(
                    icon: Icons.chevron_left_rounded,
                    onPressed: _canGoPrevious ? _goToPrevious : null,
                    alignment: Alignment.centerLeft,
                    tooltip: '上一张',
                  ),
                  _buildNavArrow(
                    icon: Icons.chevron_right_rounded,
                    onPressed: _canGoNext ? _goToNext : null,
                    alignment: Alignment.centerRight,
                    tooltip: '下一张',
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImagePreviewContent extends StatefulWidget {
  const _ImagePreviewContent({
    required this.filePath,
    this.onZoomChanged,
  });

  final String filePath;
  final ValueChanged<bool>? onZoomChanged;

  @override
  State<_ImagePreviewContent> createState() => _ImagePreviewContentState();
}

class _ImagePreviewContentState extends State<_ImagePreviewContent> {
  final TransformationController _transformController =
      TransformationController();
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _transformController.addListener(_onTransformChanged);
  }

  @override
  void didUpdateWidget(covariant _ImagePreviewContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onZoomChanged != widget.onZoomChanged && !_zoomed) {
      widget.onZoomChanged?.call(false);
    }
  }

  void _onTransformChanged() {
    final zoomed = _transformController.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) {
      setState(() => _zoomed = zoomed);
      widget.onZoomChanged?.call(zoomed);
    }
  }

  @override
  void dispose() {
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: _transformController,
      panEnabled: _zoomed,
      minScale: 0.6,
      maxScale: 5,
      child: Center(
        child: Image.file(
          File(widget.filePath),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const Center(
            child: Icon(
              Icons.broken_image_outlined,
              size: 64,
              color: Colors.white38,
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoPreviewContent extends StatefulWidget {
  const _VideoPreviewContent({required this.filePath});

  final String filePath;

  @override
  State<_VideoPreviewContent> createState() => _VideoPreviewContentState();
}

class _VideoPreviewContentState extends State<_VideoPreviewContent> {
  late final Player _player;
  late final VideoController _controller;
  bool _showControls = true;
  Timer? _hideTimer;
  double _currentPosition = 0;
  double _duration = 1;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    MediaKitBootstrap.ensureInitialized();
    _player = Player();
    _controller = VideoController(_player);
    unawaited(_player.open(Media(widget.filePath)));

    _player.stream.position.listen((position) {
      if (mounted) {
        setState(() {
          _currentPosition = position.inMilliseconds.toDouble();
        });
      }
    });

    _player.stream.duration.listen((duration) {
      if (mounted && duration.inMilliseconds > 0) {
        setState(() {
          _duration = duration.inMilliseconds.toDouble();
        });
      }
    });

    _player.stream.playing.listen((playing) {
      if (mounted) {
        setState(() {
          _isPlaying = playing;
        });
      }
    });

    _resetHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    unawaited(_player.dispose());
    super.dispose();
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    setState(() {
      _showControls = true;
    });
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isPlaying) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _onSeek(double value) {
    _resetHideTimer();
    final position = Duration(milliseconds: value.toInt());
    _player.seek(position);
  }

  void _togglePlay() {
    _resetHideTimer();
    if (_isPlaying) {
      _player.pause();
    } else {
      _player.play();
    }
  }

  String _formatDuration(double milliseconds) {
    final duration = Duration(milliseconds: milliseconds.toInt());
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (_) => _resetHideTimer(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 1200, maxHeight: 760),
              color: Colors.black,
              child: Video(
                controller: _controller,
                controls: NoVideoControls,
                fill: Colors.black,
              ),
            ),
          ),
          if (!_isPlaying)
            Center(
              child: GestureDetector(
                onTap: _togglePlay,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              ),
            ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            left: 0,
            right: 0,
            bottom: _showControls ? 0 : -80,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.7),
                  ],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: Colors.white,
                        inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
                        thumbColor: Colors.white,
                        overlayColor: Colors.white.withValues(alpha: 0.1),
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 14,
                        ),
                      ),
                      child: Slider(
                        value: _currentPosition.clamp(0, _duration),
                        max: _duration,
                        onChanged: _onSeek,
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(_currentPosition),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                        IconButton(
                          iconSize: 28,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: Icon(
                            _isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                          ),
                          onPressed: _togglePlay,
                        ),
                        Text(
                          _formatDuration(_duration),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryOption {
  const _CategoryOption({required this.key, required this.label});

  final String key;
  final String label;
}
