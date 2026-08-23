import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'all_folders_screen.dart';
import 'folder_card.dart';
import 'dart:ui'; // For BackdropFilter
import '../../core/database/database_helper.dart';
import '../../core/models/folder_model.dart';
import '../../core/utils/metadata_extractor.dart';
import '../../core/widgets/success_confetti_popup.dart';
import '../../theme/app_theme.dart';
import 'add_folder_dialog.dart';
import 'edit_folder_dialog.dart';
import '../../core/widgets/gradient_scaffold.dart'; // New
import '../../core/widgets/glass_container.dart'; // New
import '../links/link_screen.dart';
import '../links/folder_suggestion_dialog.dart';
import 'package:flutter/services.dart';
import '../search/search_delegate.dart';
import '../../core/sync/sync_manager.dart';
import 'dart:async';
import '../../core/auth/user_session_manager.dart';
import '../../core/theme/theme_manager.dart';
import '../admin/admin_screen.dart';
import '../onboarding/initial_setup_screen.dart';
import '../profile/profile_screen.dart';
import '../../core/models/link_model.dart';
import '../links/link_card.dart';
import 'all_saves_screen.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/utils/url_utils.dart';
import '../links/edit_link_dialog.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FolderScreen extends StatefulWidget {
  final String? sharedLink;

  const FolderScreen({super.key, this.sharedLink});

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  List<Folder> folders = [];
  List<LinkItem> recentLinks = [];
  int _totalLinksCount = 0;
  bool _isAdmin = false;
  bool _isLoading = false; // Added loading state
  bool _showCreateFolderHint = false;
  StreamSubscription? _syncSubscription;
  late AnimationController _hintBounceController;
  late Animation<double> _hintBounceAnimation;
  late AnimationController _hintFadeController;
  late Animation<double> _hintFadeAnimation;
  Timer? _hintDismissTimer;

  // Static flag: true only for the first build after a cold start (process alive = not cold)
  static bool _coldStartHintShown = false;

  Future<void> _checkFirstFolderHint() async {
    // Deprecated in favor of dynamic check in _loadFolders
  }

  @override
  void initState() {
    super.initState();
    _hintBounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _hintBounceAnimation = Tween<double>(begin: 0.0, end: 6.0).animate(
      CurvedAnimation(
        parent: _hintBounceController,
        curve: Curves.easeInOut,
      ),
    );

    // Fade controller for the hint pill
    _hintFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _hintFadeAnimation = CurvedAnimation(
      parent: _hintFadeController,
      curve: Curves.easeInOut,
    );

    WidgetsBinding.instance.addObserver(this); // Register observer
    _checkAdmin();
    _init(); // This now handles loading logic

    // Listen for sync updates
    _syncSubscription = SyncManager.instance.onSyncCompleted.listen((_) {
      if (mounted) {
        _loadFolders(silent: true); // Silent refresh on sync
        _checkAdmin();
      }
    });

    // Listen for local DB changes (e.g. from Share Intent)
    DatabaseHelper.instance.onDatabaseChanged.listen((_) {
      print('[FOLDER_SCREEN] Database changed, reloading...');
      if (mounted) {
        _loadFolders(silent: true);
      }
    });

    // Show hint on cold start only (static flag resets when process dies)
    if (!_coldStartHintShown) {
      _coldStartHintShown = true;
      _triggerColdStartHint();
    }
  }

  void _triggerColdStartHint() {
    // Wait for first frame before starting animation
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      setState(() => _showCreateFolderHint = true);
      await _hintFadeController.forward(); // fade in
      // Stay visible for 2 seconds
      _hintDismissTimer = Timer(const Duration(seconds: 2), () async {
        if (!mounted) return;
        await _hintFadeController.reverse(); // fade out
        if (mounted) setState(() => _showCreateFolderHint = false);
      });
    });
  }

  // ... (dispose and didChangeAppLifecycleState remain same) ...

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncSubscription?.cancel();
    _hintBounceController.dispose();
    _hintFadeController.dispose();
    _hintDismissTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      print('[FOLDER_SCREEN] App resumed, reloading folders...');
      _loadFolders(silent: true);
      _checkPendingSave();
    }
  }

  // ... (checkAdmin, handleLogout remain same) ...

  Future<void> _checkAdmin() async {
    try {
      final role = await SyncManager.instance.remoteDataSource.fetchUserRole();
      if (mounted && role == 'admin') {
        setState(() => _isAdmin = true);
      }
    } catch (_) {}
  }

  Future<void> _handleLogout() async {
    final unsyncedFolders = await DatabaseHelper.instance.getUnsyncedFolders();
    final unsyncedLinks = await DatabaseHelper.instance.getUnsyncedLinks();
    final bool hasUnsynced = unsyncedFolders.isNotEmpty || unsyncedLinks.isNotEmpty;

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: AlertDialog(
          title: const Text('Log Out?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Are you sure you want to log out?'),
              if (hasUnsynced) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.red),
                          const SizedBox(width: 8),
                          Text(
                            'Unsynced Changes Detected',
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'You have ${unsyncedFolders.length} unsynced folder(s) and ${unsyncedLinks.length} unsynced link(s). '
                        'Logging out will permanently wipe these from your device. If you haven\'t run the database schema fix, please execute project-backend/fix_links_foreign_key.sql in your Supabase SQL Editor to allow synchronization.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.red.shade200
                              : Colors.red.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: hasUnsynced ? Colors.red : Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Log Out'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      // Push any pending local changes to cloud before wiping
      try {
        await SyncManager.instance.pushLocalChanges();
      } catch (e) {
        print('[FOLDER_SCREEN] Failed to push before logout: $e');
      }

      // Sign out from Supabase auth
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (e) {
        print('[FOLDER_SCREEN] Failed to sign out from Supabase: $e');
      }

      await UserSessionManager.clearSession();
      await DatabaseHelper.instance.clearAllData();
      SyncManager.instance.resetUserCreated();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const InitialSetupScreen()),
          (route) => false,
        );
      }
    }
  }

  /// Load folders first, then show picker if app opened via share
  Future<void> _init() async {
    print('[FOLDER_SCREEN] Initializing, sharedLink: ${widget.sharedLink}');
    await _loadFolders(silent: true); // Default is non-silent (shows loading)

    if (!mounted) {
      print('[FOLDER_SCREEN] Not mounted after loading folders');
      return;
    }

    if (widget.sharedLink != null) {
      print('[FOLDER_SCREEN] Shared link detected, scheduling folder picker');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        print('[FOLDER_SCREEN] Post frame callback - showing folder picker');
        final cleanUrl = MetadataExtractor.extractCleanUrl(widget.sharedLink!);
        _showFolderPicker(cleanUrl);
      });
    }
  }

  /// Load folders safely
  Future<void> _loadFolders({bool silent = false}) async {
    // If not silent, we want to show loading state
    if (!silent && mounted) {
      setState(() => _isLoading = true);
    }

    // Capture start time to ensure minimum loading duration
    final startTime = DateTime.now();
    // Duration for the welcome animation to complete comfortably
    final minDuration = silent
        ? Duration.zero
        : const Duration(milliseconds: 3500);

    // Calculate remaining time to wait
    if (!silent) {
      final elapsed = DateTime.now().difference(startTime);
      if (elapsed < minDuration) {
        await Future.delayed(minDuration - elapsed);
      }
    }

    // Query folders after the delay to ensure we fetch the most recent sync results
    final result = await DatabaseHelper.instance.getFolders();
    final linkResult = await DatabaseHelper.instance.getRecentLinks(limit: 3);
    final totalLinks = await DatabaseHelper.instance.getLinksCount();

    if (!mounted) return;

    final loadedFolders = result.map((e) => Folder.fromMap(e)).toList();

    setState(() {
      folders = loadedFolders;
      folders.sort((a, b) {
        int cmp = b.itemCount.compareTo(a.itemCount);
        if (cmp == 0) return b.createdAt.compareTo(a.createdAt);
        return cmp;
      });
      recentLinks = linkResult.map((e) => LinkItem.fromMap(e)).toList();
      _totalLinksCount = totalLinks;
      // _showCreateFolderHint is now managed by _triggerColdStartHint only
      // Only clear loading state if this was a blocking load
      // This prevents background silent refreshes (e.g. sync) from interrupting the welcome animation
      if (!silent) {
        _isLoading = false;
      }
    });

    // Sync folder list to App Group so Share Extension can display them
    _syncFoldersToAppGroup(loadedFolders);
  }

  /// Serializes folder list to JSON and pushes it to the iOS App Group via platform channel.
  /// The Share Extension reads this to show folder names without needing the main app open.
  Future<void> _syncFoldersToAppGroup(List<Folder> folderList) async {
    try {
      const channel = MethodChannel('shared_link');
      final jsonList = folderList
          .where((f) => f.id != null)
          .map((f) => {'id': f.id, 'name': f.name, 'icon': f.icon})
          .toList();
      final jsonString = jsonList.isNotEmpty
          ? '[${jsonList.map((m) => '{"id":${m["id"]},"name":"${(m["name"] as String).replaceAll('"', '\\"')}","icon":"${m["icon"]}"}').join(',')}]'
          : '[]';
      await channel.invokeMethod('saveFolders', jsonString);
    } catch (e) {
      print('[FOLDER_SCREEN] Failed to sync folders to App Group: $e');
    }
  }

  /// Called on app resume — checks if Share Extension saved a link directly.
  /// If yes, inserts it into the correct folder (creating a new folder if requested) and triggers a sync.
  Future<void> _checkPendingSave() async {
    try {
      const channel = MethodChannel('shared_link');
      final result = await channel.invokeMethod<Map<Object?, Object?>>('getPendingSave');
      if (result == null) return;

      final link = result['link'] as String?;
      final folderIdStr = result['folderId'] as String?;
      if (link == null || link.isEmpty) return;

      // Clear immediately to avoid duplicate processing
      await channel.invokeMethod('clearPendingSave');

      print('[FOLDER_SCREEN] Processing pending save from Share Extension: $link');

      int? targetFolderId;
      String targetFolderName = 'Saved Links';

      // Check if user chose to create a new folder from the Share Extension
      if (folderIdStr != null && folderIdStr.startsWith('new:')) {
        final newName = folderIdStr.substring(4).trim();
        if (newName.isNotEmpty) {
          final newFolderId = await DatabaseHelper.instance.insertFolder({
            'name': newName,
            'icon': '0xe3b0',
          });
          targetFolderId = newFolderId;
          targetFolderName = newName;
          print('[FOLDER_SCREEN] Created new folder from Share Extension: $newName (ID: $newFolderId)');
        }
      } else if (folderIdStr != null && folderIdStr.isNotEmpty) {
        final fid = int.tryParse(folderIdStr);
        final found = folders.where((f) => f.id == fid).firstOrNull;
        if (found != null && found.id != null) {
          targetFolderId = found.id;
          targetFolderName = found.name;
        }
      }

      // Fallback to first existing folder if needed
      if (targetFolderId == null && folders.isNotEmpty) {
        targetFolderId = folders.first.id;
        targetFolderName = folders.first.name;
      }

      if (targetFolderId == null) return;

      final cleanUrl = MetadataExtractor.extractCleanUrl(link);
      if (cleanUrl.isEmpty) return;

      final parsedUri = Uri.tryParse(cleanUrl);
      final domain = parsedUri?.host.replaceAll('www.', '') ?? '';
      final title = domain.isNotEmpty ? domain : 'Link';

      // Save the link
      await DatabaseHelper.instance.insertLink({
        'folder_id': targetFolderId,
        'url': cleanUrl,
        'title': title,
        'domain': domain,
        'image_url': null,
        'notes': '',
      });

      print('[FOLDER_SCREEN] Pending link saved to folder $targetFolderName (ID: $targetFolderId): $cleanUrl');
      _loadFolders(silent: true);

      // Trigger sync
      SyncManager.instance.pushLocalChanges().catchError((_) {});

    } catch (e) {
      print('[FOLDER_SCREEN] Error checking pending save: $e');
    }
  }

  Future<void> _deleteFolder(Folder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Folder?'),
        content: const Text(
          'This will delete the folder and all links inside it. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppTheme.errorColor),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await DatabaseHelper.instance.deleteFolder(folder.id!);

        _loadFolders(silent: true);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Folder deleted')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete folder')),
          );
        }
      }
    }
  }

  /// Bottom sheet to pick folder for shared link (with suggestions)
  void _showFolderPicker(String link) async {
    print('[FOLDER_PICKER] Starting with link: $link');
    // Extract metadata for suggestions
    try {
      print('[FOLDER_PICKER] Extracting metadata and content...');
      final metadata = await MetadataExtractor.extractMetadata(link);
      final title = metadata['title'] ?? '';
      final description = metadata['description'] ?? '';
      final content = metadata['content'] ?? '';

      print('[FOLDER_PICKER] Metadata extracted - title: $title');

      if (!mounted) {
        print('[FOLDER_PICKER] Widget not mounted after metadata extraction');
        return;
      }

      print(
        '[FOLDER_PICKER] Showing suggestion dialog with ${folders.length} folders',
      );
      // Show folder suggestion dialog
      final selectedFolder = await showDialog<Folder>(
        context: context,
        barrierDismissible: false,
        builder: (_) => FolderSuggestionDialog(
          linkUrl: link,
          linkTitle: title,
          linkDescription: description,
          linkContent: content,
          folders: folders,
        ),
      );

      print('[FOLDER_PICKER] Dialog returned: $selectedFolder');

      if (selectedFolder == null || !mounted) {
        print('[FOLDER_PICKER] No folder selected or widget unmounted');
        return;
      }

      // Save link to selected folder
      await _saveLinkToFolder(link, selectedFolder, title, description);
    } catch (e, st) {
      print('[FOLDER_PICKER] Error: $e');
      print('[FOLDER_PICKER] Stack trace: $st');
      // Fallback to simple folder picker if metadata extraction fails
      if (!mounted) return;
      _showSimpleFolderPicker(link);
    }
  }

  /// Simple folder picker (fallback)
  void _showSimpleFolderPicker(String link) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (_) {
        return SafeArea(
          child: SizedBox(
            height: 400,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Save to folder', style: AppTheme.heading3),
                ),
                Expanded(
                  child: folders.isEmpty
                      ? const Center(child: Text('No folders available'))
                      : ListView.builder(
                          itemCount: folders.length,
                          itemBuilder: (context, index) {
                            final folder = folders[index];
                            return ListTile(
                              leading: Icon(
                                _parseIcon(folder.icon),
                                color: AppTheme.primaryColor,
                              ),
                              title: Text(
                                folder.name,
                                style: AppTheme.bodyLarge,
                              ),
                              onTap: () async {
                                final navigator = Navigator.of(context);
                                await _saveLinkToFolder(link, folder, link, '');
                                if (!mounted) return;
                                navigator.pop();
                                SystemNavigator.pop();
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Save link to folder with metadata
  Future<void> _saveLinkToFolder(
    String url,
    Folder folder,
    String title,
    String description,
  ) async {
    try {
      // Use title if available, otherwise use domain
      String displayTitle = title;
      if (displayTitle.isEmpty) {
        try {
          final uri = Uri.parse(url);
          displayTitle = uri.host.replaceAll('www.', '');
        } catch (e) {
          displayTitle = 'Link';
        }
      }

      await DatabaseHelper.instance.insertLink({
        'folder_id': folder.id,
        'url': url,
        'title': displayTitle,
        'domain': _extractDomain(url),
      });

      if (!mounted) return;

      // Show success popup
      await SuccessConfettiPopup.show(
        context: context,
        title: 'Link Saved!',
        message: 'Your link has been saved successfully',
      );

      // Synch immediately to update active status
      SyncManager.instance.sync();

      // Close the app
      final navigator = Navigator.of(context);
      navigator.pop(); // closes dialog/sheet
      SystemNavigator.pop(); // finishes share activity
    } catch (e) {
      print('Error saving link: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to save link')));
    }
  }

  String _extractDomain(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.replaceAll('www.', '');
    } catch (e) {
      return '';
    }
  }

  IconData _parseIcon(String iconCode) {
    // Map of icon codes to MaterialDesignIcons
    final iconMap = {
      // Folder Icons
      '0xe3b0': Icons.folder,
      '0xf06b': Icons.folder_open,
      '0xf07b': Icons.folder_special,
      // Document Icons
      '0xf1c6': Icons.description,
      '0xf0f6': Icons.file_present,
      '0xe80c': Icons.article,
      '0xe8d0': Icons.note,
      '0xe3c9': Icons.notes,
      // Media Icons
      '0xe8a5': Icons.image,
      '0xe04b': Icons.video_library,
      '0xf001': Icons.music_note,
      '0xe3fc': Icons.photo,
      '0xe04e': Icons.videocam,
      '0xe3b1': Icons.collections,
      // Organization Icons
      '0xe875': Icons.bookmark,
      '0xe839': Icons.favorite,
      '0xf591': Icons.star,
      '0xe5ca': Icons.label,
      '0xe3b8': Icons.category,
      '0xe863': Icons.archive,
      // Business/Work Icons
      '0xe8e0': Icons.work,
      '0xe8d5': Icons.business,
      '0xe8d3': Icons.engineering,
      '0xf1bc': Icons.assignment,
      '0xe8dd': Icons.task,
      '0xe8dc': Icons.checklist,
      '0xe192': Icons.attach_money,
      '0xf170': Icons.trending_up,
      // Personal Icons
      '0xe871': Icons.home,
      '0xf0e6': Icons.school,
      '0xf086': Icons.lightbulb,
      '0xe919': Icons.psychology,
      '0xf195': Icons.travel_explore,
      '0xf04a': Icons.sports_basketball,
      // Tech Icons
      '0xf123': Icons.code,
      '0xf0d6': Icons.settings,
      '0xe30b': Icons.computer,
      '0xe325': Icons.phone_android,
      '0xe3ce': Icons.terminal,
      '0xe30c': Icons.storage,
      // Shopping & Lifestyle
      '0xe5dd': Icons.shopping_bag,
      '0xe53a': Icons.shopping_cart,
      '0xe32e': Icons.restaurant,
      '0xe6d3': Icons.local_cafe,
      '0xe8a0': Icons.health_and_safety,
      '0xe8c9': Icons.fitness_center,
      // Social & Communication
      '0xe0b9': Icons.people,
      '0xe0ba': Icons.person,
      '0xe0c0': Icons.mail,
      '0xe0c1': Icons.chat,
      '0xe0c2': Icons.comment,
      '0xe0c8': Icons.notifications,
      // Time & Calendar
      '0xe935': Icons.calendar_today,
      '0xe937': Icons.schedule,
      '0xe8c5': Icons.event,
      // Misc
      '0xe25c': Icons.lock,
      '0xe899': Icons.key,
      '0xe8d7': Icons.palette,
      '0xf05a': Icons.pets,
      '0xe55b': Icons.info,
      '0xe5d5': Icons.help,
    };
    return iconMap[iconCode] ?? Icons.folder;
  }

  final GlobalKey _menuButtonKey = GlobalKey();

  void _showMainMenu() async {
    final renderBox =
        _menuButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    // Calculate position: right aligned, below the button
    // We pass the top-right coordinate of the menu's desired position
    final top = offset.dy + size.height;
    final right = MediaQuery.of(context).size.width - (offset.dx + size.width);

    // Using a custom transparent route
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors
            .transparent, // We handle barrier manually for cleaner dismiss
        pageBuilder: (context, animation, secondaryAnimation) {
          return _FolderMenuOverlay(
            top: top,
            right: right,
            isAdmin: _isAdmin,
            onLogout: _handleLogout,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    if (_isLoading) {
      return GradientScaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated Logo
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutBack,
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Icon(
                      Icons.folder_copy_rounded,
                      size: 80,
                      color: colorScheme.primary,
                    ),
                  );
                },
              ),
              const SizedBox(height: 40),
              // Typewriter Text
              DefaultTextStyle(
                style: theme.textTheme.headlineSmall!.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                  letterSpacing: 1.0,
                ),
                child: TweenAnimationBuilder<int>(
                  tween: IntTween(begin: 0, end: "Welcome to I Like It".length),
                  duration: const Duration(milliseconds: 2000),
                  curve: Curves.linear,
                  builder: (context, value, child) {
                    final text = "Welcome to I Like It";
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(text.substring(0, value)),
                        // Blinking cursor effect
                        if (value < text.length)
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.0, end: 1.0),
                            duration: const Duration(milliseconds: 500),
                            builder: (context, value, child) {
                              return Opacity(
                                opacity: value > 0.5 ? 1.0 : 0.0,
                                child: Container(
                                  width: 2,
                                  height: 24,
                                  color: colorScheme.primary,
                                ),
                              );
                            },
                            onEnd: () {},
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GradientScaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          await SyncManager.instance.sync(); // Force a cloud sync
          await _loadFolders(silent: true);
          await _checkAdmin();
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Header with Logo and Profile
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(
                  top: 24,
                  left: 16,
                  right: 16,
                  bottom: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Image.asset(
                      isDark
                          ? 'assets/native_splash_transparent.png'
                          : 'assets/light_logo_transparent.png',
                      height: 54,
                    ),
                    GestureDetector(
                      key: _menuButtonKey,
                      onTap: _showMainMenu,
                      child: CircleAvatar(
                        radius: 22,
                        backgroundColor: colorScheme.primary.withOpacity(0.15),
                        child: Icon(
                          Icons.person,
                          color: colorScheme.primary,
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Search Bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: GestureDetector(
                  onTap: () => showSearch(
                    context: context,
                    delegate: GlobalSearchDelegate(),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: theme.scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: colorScheme.outline.withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search, color: theme.hintColor),
                        const SizedBox(width: 12),
                        Text(
                          'Search your saved items...',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.hintColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Recent Saves Section
            if (recentLinks.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Recent Saves',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AllSavesScreen(),
                            ),
                          );
                        },
                        child: Text(
                          'View all ($_totalLinksCount)',
                          style: TextStyle(color: colorScheme.primary),
                        ),
                        style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final link = recentLinks[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
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
                                  Icons.share,
                                  size: 18,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Share',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.primary,
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
                                  color: colorScheme.onSurface,
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
                          if (value == 'share') {
                            Share.share(link.url);
                          } else if (value == 'edit') {
                            final edited = await showDialog<bool>(
                              context: context,
                              builder: (_) => EditLinkDialog(link: link),
                            );
                            if (edited == true) {
                              _loadFolders(silent: true);
                              SyncManager.instance.sync();
                            }
                          } else if (value == 'delete') {
                            await DatabaseHelper.instance.deleteLink(link.id!);
                            _loadFolders(silent: true);
                            SyncManager.instance.sync();
                          }
                        },
                      ),
                    ),
                  );
                }, childCount: recentLinks.length),
              ),
            ],

            // Folders Section
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Folders',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (folders.length > 6)
                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const AllFoldersScreen(),
                                ),
                              ).then((_) => _loadFolders(silent: true));
                            },
                            child: Text(
                              'View all (${folders.length})',
                              style: TextStyle(color: colorScheme.primary),
                            ),
                            style: TextButton.styleFrom(
                              minimumSize: Size.zero,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                      ],
                    ),

                  ],
                ),
              ),
            ),
            if (folders.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GlassContainer(
                        borderRadius: BorderRadius.circular(100),
                        padding: const EdgeInsets.all(32),
                        child: Icon(
                          Icons.folder_open_rounded,
                          size: 64,
                          color: colorScheme.primary.withOpacity(0.5),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'No collections yet',
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Organize your favorites into folders',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton.icon(
                        onPressed: () async {
                          await _showAddFolderDialog();
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        icon: const Icon(Icons.add, size: 20),
                        label: const Text('New Folder'),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 2.3, // Match mockup proportion
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final folder = folders[index];
                    return FolderCard(
                      folder: folder,
                      onRefresh: () => _loadFolders(silent: true),
                    );
                  }, childCount: folders.length <= 6 ? folders.length : 4),
                ),
              ),

            // Extra padding at bottom for FAB
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_showCreateFolderHint) ...[
            FadeTransition(
              opacity: _hintFadeAnimation,
              child: AnimatedBuilder(
                animation: _hintBounceAnimation,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(0, -_hintBounceAnimation.value),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surface.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: colorScheme.primary.withOpacity(0.35),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.primary.withOpacity(0.18),
                            blurRadius: 16,
                            spreadRadius: 1,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.create_new_folder_rounded,
                            color: colorScheme.primary,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Tap + to create your own folder',
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: colorScheme.primary,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          FloatingActionButton(
            onPressed: () async {
              await _showAddFolderDialog();
            },
            backgroundColor: colorScheme.primary,
            elevation: 6,
            shape: const CircleBorder(),
            child: const Icon(Icons.add_rounded, size: 32, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddFolderDialog() async {
    final result = await showDialog<dynamic>(
      context: context,
      builder: (context) => const AddFolderDialog(),
    );

    if (result != null) {
      // Dismiss onboarding hint permanently once user creates their first folder
      try {
        await UserSessionManager.setHasCreatedFolder(true);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _showCreateFolderHint = false;
        });
      }

      _loadFolders(silent: true);
      SyncManager.instance.sync();

      if (result is Folder && mounted) {
        await SuccessConfettiPopup.show(
          context: context,
          title: 'Folder Created!',
          message: 'Your folder "${result.name}" has been created successfully',
        );
      }
    }
  }
}

class _FolderMenuOverlay extends StatefulWidget {
  final double top;
  final double right;
  final bool isAdmin;
  final VoidCallback onLogout;

  const _FolderMenuOverlay({
    required this.top,
    required this.right,
    required this.isAdmin,
    required this.onLogout,
  });

  @override
  State<_FolderMenuOverlay> createState() => _FolderMenuOverlayState();
}

enum _MenuPage { main, appearance }

class _FolderMenuOverlayState extends State<_FolderMenuOverlay> {
  _MenuPage _page = _MenuPage.main;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Barrier
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            behavior: HitTestBehavior.translucent,
            child: Container(color: Colors.transparent),
          ),
        ),
        // Menu
        Positioned(
          top: widget.top,
          right: widget.right,
          child: Material(
            color: Colors.transparent,
            elevation: 8, // Increased elevation
            borderRadius: BorderRadius.circular(16),
            child: GlassContainer(
              // Wrap menu in GlassContainer
              width: 260,
              padding: EdgeInsets.zero,
              borderRadius: BorderRadius.circular(16),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) {
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.1, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: FadeTransition(opacity: animation, child: child),
                  );
                },
                child: _page == _MenuPage.main
                    ? _buildMainMenu(context)
                    : _buildAppearanceMenu(context),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMainMenu(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      key: const ValueKey('main'),
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: Icon(
            Icons.person_outline,
            color: colorScheme.onSurface,
            size: 20,
          ),
          title: Text('My Profile', style: theme.textTheme.bodyMedium),
          trailing: Icon(
            Icons.chevron_right,
            color: colorScheme.onSurfaceVariant,
            size: 18,
          ),
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            );
          },
          dense: true,
        ),
        ListTile(
          leading: Icon(
            Icons.palette_outlined,
            color: colorScheme.onSurface,
            size: 20,
          ),
          title: Text('Appearance', style: theme.textTheme.bodyMedium),
          trailing: Icon(
            Icons.chevron_right,
            color: colorScheme.onSurfaceVariant,
            size: 18,
          ),
          onTap: () => setState(() => _page = _MenuPage.appearance),
          dense: true,
        ),

        if (widget.isAdmin)
          ListTile(
            leading: Icon(
              Icons.admin_panel_settings,
              color: colorScheme.primary,
              size: 20,
            ),
            title: Text(
              'Admin Dashboard',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.primary,
              ),
            ),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => AdminScreen()),
              );
            },
            dense: true,
          ),
        ListTile(
          leading: Icon(Icons.logout, color: colorScheme.error, size: 20),
          title: Text(
            'Logout',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.error,
            ),
          ),
          onTap: () {
            Navigator.pop(context);
            widget.onLogout();
          },
          dense: true,
        ),
      ],
    );
  }

  Widget _buildAppearanceMenu(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentMode = ThemeManager.instance.themeModeNotifier.value;

    return Column(
      key: const ValueKey('appearance'),
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => setState(() => _page = _MenuPage.main),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.arrow_back, color: colorScheme.onSurface, size: 18),
                const SizedBox(width: 12),
                Text(
                  'Appearance',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        _buildThemeOption(
          context,
          'System Default',
          ThemeMode.system,
          currentMode,
        ),
        _buildThemeOption(context, 'Light Mode', ThemeMode.light, currentMode),
        _buildThemeOption(context, 'Dark Mode', ThemeMode.dark, currentMode),
      ],
    );
  }

  Widget _buildThemeOption(
    BuildContext context,
    String title,
    ThemeMode mode,
    ThemeMode current,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSelected = mode == current;

    return ListTile(
      leading: Icon(
        mode == ThemeMode.light
            ? Icons.light_mode
            : mode == ThemeMode.dark
            ? Icons.dark_mode
            : Icons.brightness_auto,
        color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
        size: 20,
      ),
      title: Text(
        title,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? colorScheme.primary : colorScheme.onSurface,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check, color: colorScheme.primary, size: 18)
          : null,
      onTap: () {
        ThemeManager.instance.setThemeMode(mode);
        // Do not close menu, allow user to see change
        // Or close? User request "transition between themes is choppy" could mean
        // they want to see it instantly without menu glitching.
        // Keeping menu open allows them to switch back if they don't like it.
        // We set state to trigger rebuild of icons
        setState(() {});
      },
      dense: true,
    );
  }
}
