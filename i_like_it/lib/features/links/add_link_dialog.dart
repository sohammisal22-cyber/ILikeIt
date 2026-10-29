import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:sqflite/sqflite.dart';
import '../../core/database/database_helper.dart';
import '../../core/models/link_model.dart';
import '../../core/utils/metadata_extractor.dart';
import '../../core/widgets/success_confetti_popup.dart';
import '../../theme/app_theme.dart';

class AddLinkDialog extends StatefulWidget {
  final int folderId;

  const AddLinkDialog({super.key, required this.folderId});

  @override
  State<AddLinkDialog> createState() => _AddLinkDialogState();
}

class _AddLinkDialogState extends State<AddLinkDialog> {
  final _controller = TextEditingController();
  bool _saving = false;
  String? _errorMessage;

  void _showError(String message) {
    setState(() => _errorMessage = message);
  }

  void _clearError() {
    if (_errorMessage != null) setState(() => _errorMessage = null);
  }

  Future<void> _saveLink() async {
    print('[ADD_LINK] _saveLink called');
    _clearError();

    var url = _controller.text.trim();

    if (!url.startsWith('http')) {
      _showError('Enter a valid URL starting with http:// or https://');
      return;
    }

    // Normalize URL: remove trailing slash and query parameters for consistent comparison
    var normalizedUrl = _normalizeUrlForComparison(url);

    print(
      '[ADD_LINK] Checking duplicate for URL: $normalizedUrl in folder: ${widget.folderId}',
    );

    // Check for duplicate link URLs in this folder
    final db = await DatabaseHelper.instance.database;
    final existing = await db.query(
      'links',
      where: 'folder_id = ?',
      whereArgs: [widget.folderId],
    );

    // Check if any existing link has the same base URL
    final isDuplicate = existing.any((link) {
      final existingNormalized = _normalizeUrlForComparison(
        link['url'] as String,
      );
      return existingNormalized == normalizedUrl;
    });

    print(
      '[ADD_LINK] Found ${existing.length} total links, duplicate: $isDuplicate',
    );

    if (isDuplicate) {
      print('[ADD_LINK] Duplicate detected! Not saving.');
      if (!mounted) return;
      _showError('This link already exists in this folder');
      return;
    }

    setState(() => _saving = true);

    try {
      // Extract metadata from the URL
      final metadata = await MetadataExtractor.extractMetadata(url);
      String title = metadata['title'] ?? '';
      String imageUrl = metadata['image'] ?? '';

      // If no title found, use domain as title
      if (title.isEmpty) {
        try {
          final uri = Uri.parse(url);
          title = uri.host.replaceAll('www.', '');
        } catch (e) {
          title = 'Link';
        }
      }

      // Show dialog to let user add notes
      if (!mounted) {
        setState(() => _saving = false);
        return;
      }
      final details = await showDialog<Map<String, String>>(
        context: context,
        builder: (context) => _DetailsDialog(initialTitle: title),
      );

      // User cancelled the details dialog
      if (details == null) {
        if (mounted) setState(() => _saving = false);
        return;
      }

      // Check again for duplicates before inserting (in case dialog took a long time)
      final duplicateCheck = await db.query(
        'links',
        where: 'folder_id = ?',
        whereArgs: [widget.folderId],
      );

      final isDuplicateCheck = duplicateCheck.any((link) {
        final existingNormalized = _normalizeUrlForComparison(
          link['url'] as String,
        );
        return existingNormalized == normalizedUrl;
      });

      if (isDuplicateCheck) {
        if (!mounted) {
          setState(() => _saving = false);
          return;
        }
        setState(() => _saving = false);
        _showError('This link was already saved');
        return;
      }

      final finalTitle = details['title'] ?? title;
      final notes = details['notes'] ?? '';

      final link = LinkItem(
        folderId: widget.folderId,
        url: url,
        title: finalTitle.isNotEmpty ? finalTitle : title,
        domain: _extractDomain(url),
        imageUrl: imageUrl.isNotEmpty ? imageUrl : null,
        notes: notes,
        createdAt: DateTime.now(),
      );

      try {
        await DatabaseHelper.instance.insertLink(link.toMap());
        print('Saved link with URL: $url to folder: ${widget.folderId}');
      } on DatabaseException catch (e) {
        if (e.toString().contains('UNIQUE constraint failed')) {
          if (!mounted) {
            setState(() => _saving = false);
            return;
          }
          setState(() => _saving = false);
          _showError('This link already exists in this folder');
          return;
        }
        rethrow;
      }

      if (mounted) {
        // Show success popup
        await SuccessConfettiPopup.show(
          context: context,
          title: 'Link Saved!',
          message: 'Your link has been saved successfully',
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;

      setState(() => _saving = false);

      // Handle duplicate constraint errors
      if (e is DatabaseException &&
          e.toString().contains('UNIQUE constraint failed')) {
        _showError('This link already exists in this folder');
      } else {
        String displayError = 'Failed to save link. Please try again.';
        final lowerMsg = e.toString().toLowerCase();
        if (!lowerMsg.contains('exception') &&
            !lowerMsg.contains('api key') &&
            !lowerMsg.contains('socket') &&
            !lowerMsg.contains('supabase')) {
          displayError = 'Failed to save link: $e';
        }
        _showError(displayError);
      }
    }
  }

  String? _extractDomain(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.replaceAll('www.', '');
    } catch (e) {
      return null;
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
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inputStyle = TextStyle(
      color: isDark ? Colors.white : Colors.black,
      fontSize: 14,
    );

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
      child: AlertDialog(
        title: const Text('Add Link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              style: inputStyle,
              onChanged: (_) => _clearError(),
              decoration: InputDecoration(
                hintText: 'Paste link here',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: _errorMessage != null ? Colors.red : AppTheme.borderColor,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: _errorMessage != null ? Colors.red : AppTheme.borderColor,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: _errorMessage != null ? Colors.red : AppTheme.primaryColor,
                    width: 2,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              onSubmitted: (_) => _saveLink(),
            ),
            // Inline error message - always visible inside the dialog
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _saving ? null : _saveLink,
            child: _saving
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _DetailsDialog extends StatefulWidget {
  final String initialTitle;

  const _DetailsDialog({required this.initialTitle});

  @override
  State<_DetailsDialog> createState() => _DetailsDialogState();
}

class _DetailsDialogState extends State<_DetailsDialog> {
  late TextEditingController _titleController;
  late TextEditingController _notesController;
  late final bool _isGeneric;
  String? _errorMessage;

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
    _isGeneric = _isGenericTitle(widget.initialTitle);
    _titleController = TextEditingController(text: _isGeneric ? '' : widget.initialTitle);
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inputStyle = TextStyle(
      color: isDark ? Colors.white : Colors.black,
      fontSize: 14,
    );

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
      child: AlertDialog(
        title: const Text('Link Details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add a meaningful title to search and find your saved link easily in the future.',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white70 : AppTheme.textSecondary,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Title',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _titleController,
                autofocus: true,
                style: inputStyle,
                onChanged: (_) {
                  if (_errorMessage != null) setState(() => _errorMessage = null);
                },
                decoration: InputDecoration(
                  hintText: 'Enter link title',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: _errorMessage != null ? Colors.red : AppTheme.borderColor,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: _errorMessage != null ? Colors.red : AppTheme.borderColor,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: _errorMessage != null ? Colors.red : AppTheme.primaryColor,
                      width: 2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
              ),
              // Inline error for title field
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 15),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              const Text(
                'Notes (Optional)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notesController,
                maxLines: 3,
                style: inputStyle,
                decoration: InputDecoration(
                  hintText:
                      'Add your notes... (e.g., "Funny cat video", "Read later")',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppTheme.primaryColor,
                      width: 2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (!_isGeneric)
            TextButton(
              onPressed: () => Navigator.pop(context, {
                'title': widget.initialTitle,
                'notes': '',
              }),
              child: const Text('Skip'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final title = _titleController.text.trim();
              if (title.isEmpty) {
                setState(() => _errorMessage = 'Please enter a title to save this link');
                return;
              }
              Navigator.pop(context, {
                'title': title,
                'notes': _notesController.text.trim(),
              });
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
