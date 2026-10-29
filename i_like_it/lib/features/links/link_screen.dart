import 'package:flutter/material.dart';
import '../../core/utils/metadata_extractor.dart';
import '../../core/utils/url_utils.dart';
import '../../core/database/database_helper.dart';
import '../../core/models/link_model.dart';
import 'add_link_dialog.dart';
import 'edit_link_dialog.dart';
import 'link_card.dart';
import '../../core/sync/sync_manager.dart';
import 'dart:async';
import '../../core/widgets/gradient_scaffold.dart'; // New
import '../../core/widgets/glass_container.dart'; // New

class LinkScreen extends StatefulWidget {
  final int folderId;
  final String folderName;
  final int? highlightLinkId;

  const LinkScreen({
    super.key,
    required this.folderId,
    required this.folderName,
    this.highlightLinkId,
  });

  @override
  State<LinkScreen> createState() => _LinkScreenState();
}

class _LinkScreenState extends State<LinkScreen> {
  List<LinkItem> links = [];
  StreamSubscription? _syncSubscription;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final ScrollController _scrollController = ScrollController();
  int? _highlightedLinkId;

  List<LinkItem> get _filteredLinks {
    if (_searchQuery.isEmpty) return links;
    final lowerQuery = _searchQuery.toLowerCase();
    return links.where((link) {
      return link.title.toLowerCase().contains(lowerQuery) ||
          link.url.toLowerCase().contains(lowerQuery) ||
          (link.notes?.toLowerCase().contains(lowerQuery) ?? false);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _highlightedLinkId = widget.highlightLinkId;
    _loadLinks();

    // Listen for background sync updates
    _syncSubscription = SyncManager.instance.onSyncCompleted.listen((_) {
      if (mounted) {
        _loadLinks();
      }
    });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadLinks() async {
    final result = await DatabaseHelper.instance.getLinks(widget.folderId);

    setState(() {
      links = result.map((e) => LinkItem.fromMap(e)).toList();
    });

    if (_highlightedLinkId != null) {
      final index = links.indexWhere((l) => l.id == _highlightedLinkId);
      if (index != -1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            // Calculate estimated offset: top search field takes ~80 pixels, each item ~106 pixels
            final offset = 80.0 + (index * 106.0);
            _scrollController.animateTo(
              offset,
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
            );
          }
        });

        Timer(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() {
              _highlightedLinkId = null;
            });
          }
        });
      }
    }
  }

  Future<void> _deleteLink(LinkItem link) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Link?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await DatabaseHelper.instance.deleteLink(link.id!);
        _loadLinks();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Link deleted')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete link')),
          );
        }
      }
    }
  }

  void _showLinkDetailSheet(BuildContext context, LinkItem link) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final domain = UrlUtils.getDomainFromUrl(link.url);
    final title = link.title.isNotEmpty ? link.title : domain;
    final timeAgo = UrlUtils.formatTimestamp(link.createdAt);
    final hasNotes = link.notes != null && link.notes!.trim().isNotEmpty;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(
                color: colorScheme.primary.withOpacity(0.3),
                width: 1,
              ),
            ),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: colorScheme.onSurfaceVariant.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Thumbnail + Title row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (link.imageUrl != null && link.imageUrl!.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          link.imageUrl!,
                          width: 96,
                          height: 54,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    if (link.imageUrl != null && link.imageUrl!.isNotEmpty)
                      const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            domain.isNotEmpty ? domain : link.url,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            timeAgo,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant.withOpacity(
                                0.6,
                              ),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // Notes section
                if (hasNotes) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.primary.withOpacity(0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.note_alt_outlined,
                              size: 16,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Notes',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          link.notes!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          final edited = await showDialog<bool>(
                            context: context,
                            builder: (_) => EditLinkDialog(link: link),
                          );
                          if (edited == true) {
                            _loadLinks();
                            SyncManager.instance.sync();
                          }
                        },
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(color: colorScheme.outline),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          String finalUrl = MetadataExtractor.extractCleanUrl(
                            link.url,
                          );
                          if (!finalUrl.startsWith('http://') &&
                              !finalUrl.startsWith('https://')) {
                            finalUrl = 'https://$finalUrl';
                          }
                          UrlUtils.launchBrowserOrApp(context, finalUrl);
                        },
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: const Text('Open Link'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final double appBarHeight = widget.folderName.length > 50
        ? 160.0
        : (widget.folderName.length > 30 ? 140.0 : 100.0);
    final double titleFontSize = widget.folderName.length > 50
        ? 15.0
        : (widget.folderName.length > 30 ? 17.0 : 20.0);

    return GradientScaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          await SyncManager.instance.sync();
          await _loadLinks();
        },
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: appBarHeight,
              backgroundColor: Colors.transparent, // Transparent for gradient
              surfaceTintColor: Colors.transparent,
              leading: IconButton(
                icon: GlassContainer(
                  padding: const EdgeInsets.all(8),
                  borderRadius: BorderRadius.circular(50),
                  child: Icon(
                    Icons.arrow_back,
                    size: 20,
                    color: colorScheme.onSurface,
                  ),
                ),
                onPressed: () => Navigator.pop(context),
              ),
              flexibleSpace: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final double topPadding = MediaQuery.of(context).padding.top;
                  final double collapsedHeight = kToolbarHeight + topPadding;
                  // If current height is close to collapsed height, it is collapsed
                  final bool isCollapsed =
                      constraints.maxHeight <= collapsedHeight + 20.0;

                  return FlexibleSpaceBar(
                    title: Text(
                      widget.folderName,
                      textAlign: TextAlign.center,
                      maxLines: isCollapsed ? 1 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: isCollapsed ? 16.0 : titleFontSize,
                        letterSpacing: -0.5,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    centerTitle: true,
                    titlePadding: EdgeInsets.symmetric(
                      horizontal: 56,
                      vertical: isCollapsed ? 12 : 16,
                    ),
                  );
                },
              ),
            ),

            if (links.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GlassContainer(
                        padding: const EdgeInsets.all(32),
                        borderRadius: BorderRadius.circular(100),
                        child: Icon(
                          Icons.link_off_rounded,
                          size: 64,
                          color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'No links here',
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Save your first link to this collection',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final added = await showDialog<bool>(
                            context: context,
                            builder: (_) =>
                                AddLinkDialog(folderId: widget.folderId),
                          );
                          if (added == true) {
                            _loadLinks();
                            SyncManager.instance.sync();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                        ),
                        icon: const Icon(Icons.add_link, size: 20),
                        label: const Text('Add Link'),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _searchQuery = value),
                    decoration: InputDecoration(
                      hintText: 'Search links...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                ),
              ),
              if (_filteredLinks.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          size: 64,
                          color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No results found',
                          style: theme.textTheme.titleLarge,
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final link = _filteredLinks[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: LinkCard(
                        link: link,
                        highlight: link.id == _highlightedLinkId,
                        onTap: () {
                          _showLinkDetailSheet(context, link);
                        },
                        trailing: PopupMenuButton(
                          icon: Icon(
                            Icons.more_vert,
                            color: colorScheme.onSurfaceVariant,
                            size: 20,
                          ),
                          padding: EdgeInsets.zero,
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'share',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.share_outlined,
                                    size: 18,
                                    color: colorScheme.onSurface,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Share',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                    color: colorScheme.onSurface,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Edit',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                    color: colorScheme.error,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Delete',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.error,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          onSelected: (value) async {
                            if (value == 'edit') {
                              final edited = await showDialog<bool>(
                                context: context,
                                builder: (_) => EditLinkDialog(link: link),
                              );
                              if (edited == true) {
                                _loadLinks();
                                SyncManager.instance.sync();
                              }
                            } else if (value == 'delete') {
                              await _deleteLink(link);
                              SyncManager.instance.sync();
                            } else if (value == 'share') {
                              UrlUtils.shareLink(context, link.url);
                            }
                          },
                        ),
                      ),
                    );
                    }, childCount: _filteredLinks.length),
                  ),
                ),
              ],

            // Fab padding space
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
      floatingActionButton: links.isEmpty
          ? null
          : FloatingActionButton(
              backgroundColor: colorScheme.primary,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              onPressed: () async {
                final added = await showDialog<bool>(
                  context: context,
                  builder: (_) => AddLinkDialog(folderId: widget.folderId),
                );
                if (added == true) {
                  _loadLinks();
                  SyncManager.instance.sync();
                }
              },
              child: Icon(
                Icons.add_link,
                size: 28,
                color: colorScheme.onPrimary,
              ),
            ),
    );
  }
}
