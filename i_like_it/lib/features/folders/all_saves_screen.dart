import 'package:flutter/material.dart';
import '../../core/database/database_helper.dart';
import '../../core/models/link_model.dart';
import '../../core/utils/metadata_extractor.dart';
import '../../core/utils/url_utils.dart';
import '../../core/widgets/gradient_scaffold.dart';
import '../links/link_card.dart';
import '../links/edit_link_dialog.dart';
import '../../core/sync/sync_manager.dart';
import 'dart:async';

class AllSavesScreen extends StatefulWidget {
  const AllSavesScreen({super.key});

  @override
  State<AllSavesScreen> createState() => _AllSavesScreenState();
}

class _AllSavesScreenState extends State<AllSavesScreen> {
  List<LinkItem> links = [];
  bool isLoading = true;
  StreamSubscription? _syncSubscription;

  @override
  void initState() {
    super.initState();
    _loadLinks();
    _syncSubscription = SyncManager.instance.onSyncCompleted.listen((_) {
      if (mounted) _loadLinks();
    });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadLinks() async {
    final result = await DatabaseHelper.instance.getAllLinks();
    if (mounted) {
      setState(() {
        links = result.map((e) => LinkItem.fromMap(e)).toList();
        isLoading = false;
      });
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GradientScaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: const Text('All Saves'),
            pinned: true,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
          ),
          if (isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (links.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Text(
                  'No saved links found.',
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final link = links[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: LinkCard(
                      link: link,
                      onTap: () {
                        String finalUrl = MetadataExtractor.extractCleanUrl(
                          link.url,
                        );
                        if (!finalUrl.startsWith('http://') &&
                            !finalUrl.startsWith('https://')) {
                          finalUrl = 'https://$finalUrl';
                        }
                        UrlUtils.launchBrowserOrApp(context, finalUrl);
                      },
                      trailing: PopupMenuButton(
                        icon: Icon(
                          Icons.more_vert,
                          color: theme.colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                        padding: EdgeInsets.zero,
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'share',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.share,
                                  size: 18,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Share',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.primary,
                                  ),
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
                                  color: theme.colorScheme.onSurface,
                                ),
                                const SizedBox(width: 8),
                                Text('Edit', style: theme.textTheme.bodyMedium),
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
                                  color: theme.colorScheme.error,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Delete',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        onSelected: (value) async {
                          if (value == 'share') {
                            UrlUtils.shareLink(context, link.url);
                          } else if (value == 'edit') {
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
                          }
                        },
                      ),
                    ),
                  );
                }, childCount: links.length),
              ),
            ),
        ],
      ),
    );
  }
}
