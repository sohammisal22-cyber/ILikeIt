import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/auth/user_session_manager.dart';
import '../../core/database/database_helper.dart';
import '../../core/models/folder_model.dart';
import '../../core/utils/metadata_extractor.dart';
import '../../core/widgets/success_confetti_popup.dart';
import '../../theme/app_theme.dart';
import '../links/folder_suggestion_dialog.dart';
import '../../core/widgets/gradient_scaffold.dart'; // New
import '../onboarding/initial_setup_screen.dart';
import '../../core/sync/sync_manager.dart';

class ShareSaveScreen extends StatefulWidget {
  final String sharedLink;
  final VoidCallback? onLinkSaved;

  const ShareSaveScreen({
    super.key,
    required this.sharedLink,
    this.onLinkSaved,
  });

  @override
  State<ShareSaveScreen> createState() => _ShareSaveScreenState();
}

class _ShareSaveScreenState extends State<ShareSaveScreen> {
  List<Folder> folders = [];
  bool loading = true;
  bool _isLoggedIn = true;
  late final String cleanUrl;

  @override
  void initState() {
    super.initState();
    cleanUrl = MetadataExtractor.extractCleanUrl(widget.sharedLink);
    _checkLoginAndProceed();
  }

  void _checkLoginAndProceed() {
    if (UserSessionManager.email == null) {
      setState(() => _isLoggedIn = false);
    } else {
      setState(() => _isLoggedIn = true);
      _loadFoldersAndShowSuggestions();
    }
  }

  Future<void> _navigateToLogin() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const InitialSetupScreen()));
    // After returning from login screen, re-check login status
    _checkLoginAndProceed();
  }

  Future<void> _closeApp() async {
    widget.onLinkSaved?.call();
    const platform = MethodChannel('shared_link');
    try {
      await platform.invokeMethod('closeApp');
    } catch (e) {
      print('Error closing app: $e');
    }
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  Future<void> _loadFoldersAndShowSuggestions() async {
    // Check if we extracted a valid URL (should start with http/https)
    if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
      print('[SHARE_SCREEN] No valid URL found in shared text: $cleanUrl');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No valid link found in shared text'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      // Wait for the snackbar to be readable, then close the app
      await Future.delayed(const Duration(seconds: 2));

      await _closeApp();
      return;
    }

    print('[SHARE_SCREEN] Loading folders...');
    final db = await DatabaseHelper.instance.database;
    final result = await db.query(
      'folders',
      where: 'is_deleted = 0',
      orderBy: 'created_at DESC',
    );

    if (!mounted) return;

    setState(() {
      folders = result.map((e) => Folder.fromMap(e)).toList();
      loading = false;
    });

    // Show suggestion dialog after folders are loaded
    _showSuggestionDialog();
  }

  Future<void> _showSuggestionDialog() async {
    print('[SHARE_SCREEN] Showing suggestion dialog');
    try {
      print('[SHARE_SCREEN] Extracting metadata and content...');
      final metadata = await MetadataExtractor.extractMetadata(cleanUrl);
      String title = metadata['title'] ?? '';
      final description = metadata['description'] ?? '';
      final content = metadata['content'] ?? '';
      final imageUrl = metadata['image'] ?? '';

      // Extract extra text from sharedLink (often contains the real title!)
      String sharedText = widget.sharedLink.replaceAll(cleanUrl, '').trim();
      if (sharedText.isNotEmpty) {
        // Clean up common share prefixes
        sharedText = sharedText.replaceAll(
          RegExp(r'^Check this out:\s*', caseSensitive: false),
          '',
        );

        // Use shared text if it's substantial, or if the extracted title is generic
        if (sharedText.length > 3) {
          title = sharedText;
        } else if (title.isEmpty ||
            title.contains('Link') ||
            title == 'YouTube Video') {
          title = sharedText.isNotEmpty ? sharedText : title;
        }
      }

      if (!mounted) {
        print('[SHARE_SCREEN] Widget not mounted after metadata extraction');
        return;
      }

      print(
        '[SHARE_SCREEN] Showing suggestion dialog with ${folders.length} folders',
      );
      // Show folder suggestion dialog
      final selectedFolder = await showDialog<Folder>(
        context: context,
        barrierDismissible: false,
        builder: (_) => FolderSuggestionDialog(
          linkUrl: cleanUrl,
          linkTitle: title,
          linkDescription: description,
          linkContent: content,
          folders: folders,
        ),
      );

      print('[SHARE_SCREEN] Dialog returned: $selectedFolder');

      if (selectedFolder == null || !mounted) {
        print('[SHARE_SCREEN] No folder selected or widget unmounted');
        // Close the app if no folder selected
        await _closeApp();
        return;
      }

      // Save link to selected folder
      // Show edit dialog
      if (!mounted) return;

      final result = await showDialog<Map<String, String>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _EditLinkDialog(title: title, url: cleanUrl),
      );

      if (result == null) {
        print('[SHARE_SCREEN] Edit dialog cancelled');
        // If cancelled, close the app as this is a "Save" flow interruption
        await _closeApp();
        return;
      }

      await _saveLinkToFolder(
        cleanUrl,
        selectedFolder,
        result['title'] ?? title,
        description,
        result['note'] ?? '',
        imageUrl,
      );
    } catch (e, st) {
      print('[SHARE_SCREEN] Error in suggestion: $e');
      print('[SHARE_SCREEN] Stack: $st');
      // If metadata extraction fails, show simple picker
      if (!mounted) return;
      _showSimpleFolderPicker();
    }
  }

  /// Simple folder picker (fallback)
  void _showSimpleFolderPicker() {
    print('[SHARE_SCREEN] Showing simple folder picker (fallback)');
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
                                Icons.folder,
                                color: AppTheme.primaryColor,
                              ),
                              title: Text(
                                folder.name,
                                style: AppTheme.bodyLarge,
                              ),
                              onTap: () async {
                                // Show edit dialog even for fallback
                                final result =
                                    await showDialog<Map<String, String>>(
                                      context: context,
                                      barrierDismissible: false,
                                      builder: (_) => _EditLinkDialog(
                                        title: cleanUrl,
                                        url: cleanUrl,
                                      ),
                                    );

                                if (result == null) return;

                                await _saveLinkToFolder(
                                  cleanUrl,
                                  folder,
                                  result['title'] ?? cleanUrl,
                                  '',
                                  result['note'] ?? '',
                                  '',
                                );
                                // Removed redundant pops as _saveLinkToFolder handles closing the app
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

  Future<void> _saveLinkToFolder(
    String url,
    Folder folder,
    String title,
    String description,
    String note,
    String imageUrl,
  ) async {
    try {
      var normalizedUrl = _normalizeUrlForComparison(url);

      print(
        '[SHARE_SCREEN] Checking duplicate for URL: $normalizedUrl in folder: ${folder.id}',
      );

      // Check for duplicate link URLs in this folder
      final db = await DatabaseHelper.instance.database;
      final existing = await db.query(
        'links',
        where: 'folder_id = ?',
        whereArgs: [folder.id],
      );

      // Check if any existing link has the same base URL
      final isDuplicate = existing.any((link) {
        final existingNormalized = _normalizeUrlForComparison(
          link['url'] as String,
        );
        return existingNormalized == normalizedUrl;
      });

      if (isDuplicate) {
        print('[SHARE_SCREEN] Duplicate detected! Not saving.');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This link already exists in this folder'),
          ),
        );

        // Wait a moment for SnackBar to be visible, then close the app
        await Future.delayed(const Duration(seconds: 1));

        if (!mounted) return;

        // Close the app using platform channel to return to caller
        await _closeApp();
        return;
      }

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
        'image_url': imageUrl.isNotEmpty ? imageUrl : null,
        'notes': note,
      });

      print('[SHARE_SCREEN] Saved link to folder ${folder.id}');

      // Force a sync so it's instantly available in Supabase before the app closes
      print('[SHARE_SCREEN] Triggering cloud push...');
      try {
        await SyncManager.instance.pushLocalChanges().timeout(
          const Duration(seconds: 4),
        );
        print('[SHARE_SCREEN] Cloud push completed.');
      } catch (e) {
        print(
          '[SHARE_SCREEN] Cloud push timed out or failed, will sync next time app opens: $e',
        );
      }

      print('[SHARE_SCREEN] Triggering Confetti Popup (mounted: $mounted)');
      if (!mounted) {
        print('[SHARE_SCREEN] ABORTING: Not mounted!');
        return;
      }

      // Show success popup
      await SuccessConfettiPopup.show(
        context: context,
        title: 'Link Saved!',
        message: 'Your link has been saved successfully',
      );
      print('[SHARE_SCREEN] Confetti Popup finished, closing app...');

      // Close the app using platform channel to return to caller
      await _closeApp();
    } catch (e, st) {
      print('SAVE FAILED: $e');
      print('$st');

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to save link')));

      // Wait a moment for SnackBar to be visible, then close the app
      await Future.delayed(const Duration(seconds: 1));

      if (!mounted) return;

      // Close the app using platform channel to return to caller
      await _closeApp();
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

  String _normalizeUrlForComparison(String url) {
    try {
      final uri = Uri.parse(url);
      // Remove trailing slash and query parameters for comparison
      String path = uri.path;
      if (path.endsWith('/') && path.length > 1) {
        path = path.substring(0, path.length - 1);
      }
      // Return scheme + host + path (ignore query and fragment)
      return '${uri.scheme}://${uri.host}$path';
    } catch (e) {
      // Fallback: just remove trailing slash
      return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    }
  }

  @override
  void dispose() {
    print('[SHARE_SCREEN] ShareSaveScreen DISPOSED');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Show login required screen if user is not logged in
    if (!_isLoggedIn) {
      return GradientScaffold(
        appBar: AppBar(
          title: const Text('Save Link'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleTextStyle: theme.textTheme.headlineSmall?.copyWith(fontSize: 20),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => _closeApp(),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.lock_outline_rounded,
                    size: 56,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Login Required',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'You need to log in to your iLikeIt account before you can save links.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _navigateToLogin,
                    icon: const Icon(Icons.login_rounded),
                    label: const Text(
                      'Log In',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Save link to'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: theme.textTheme.headlineSmall?.copyWith(fontSize: 20),
      ),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _EditLinkDialog extends StatefulWidget {
  final String title;
  final String url;

  const _EditLinkDialog({required this.title, required this.url});

  @override
  State<_EditLinkDialog> createState() => _EditLinkDialogState();
}

class _EditLinkDialogState extends State<_EditLinkDialog> {
  late TextEditingController _titleController;
  late TextEditingController _noteController;
  late final bool _isGeneric;

  bool _isGenericTitle(String title) {
    final t = title.toLowerCase().trim();
    return t == 'instagram - reel' || 
           t == 'instagram link' || 
           t == 'instagram' ||
           t == 'instagram- reel' ||
           t == 'shared link' ||
           t == 'facebook' ||
           t == 'facebook link' ||
           t == 'facebook post' ||
           t == 'facebook watch' ||
           t == 'facebook video' ||
           t.startsWith('facebook -') ||
           t.startsWith('facebook-');
  }

  @override
  void initState() {
    super.initState();
    _isGeneric = _isGenericTitle(widget.title);
    _titleController = TextEditingController(text: _isGeneric ? '' : widget.title);
    _noteController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a title to save this link'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    Navigator.pop(context, {
      'title': title,
      'note': _noteController.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Link Details'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.url,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white70
                    : AppTheme.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            Text(
              'Add a meaningful title to search and find your saved link easily in the future.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white70
                    : AppTheme.textSecondary,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              autofocus: true,
              style: Theme.of(context).textTheme.bodyMedium,
              decoration: InputDecoration(
                labelText: 'Title',
                hintText: 'Enter link title',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _noteController,
              maxLines: 3,
              style: Theme.of(context).textTheme.bodyMedium,
              decoration: InputDecoration(
                labelText: 'Notes (Optional)',
                alignLabelWithHint: true,
                hintText: 'Add your notes...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
