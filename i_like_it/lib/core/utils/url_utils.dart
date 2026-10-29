import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

class UrlUtils {
  /// Safely share a URL on iOS and other platforms.
  /// Computes sharePositionOrigin for iOS/iPad UIPopoverPresentationController to prevent crashes,
  /// and passes Uri so iOS recognizes it as a real URL rather than plain text.
  static Future<void> shareLink(BuildContext context, String url) async {
    String cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return;

    if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
      cleanUrl = 'https://$cleanUrl';
    }

    // iOS/iPad requires a non-nil sharePositionOrigin for UIPopoverPresentationController
    Rect? sharePositionOrigin;
    try {
      final box = context.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        sharePositionOrigin = box.localToGlobal(Offset.zero) & box.size;
      }
    } catch (_) {}

    // Fallback origin to the center of the screen
    if (sharePositionOrigin == null || sharePositionOrigin.isEmpty) {
      try {
        final size = MediaQuery.of(context).size;
        sharePositionOrigin = Rect.fromCenter(
          center: Offset(size.width / 2, size.height / 2),
          width: 10,
          height: 10,
        );
      } catch (_) {}
    }

    await Share.share(
      cleanUrl,
      sharePositionOrigin: sharePositionOrigin,
    );
  }
  static Future<void> launchBrowserOrApp(
    BuildContext context,
    String url,
  ) async {
    final uri = Uri.parse(url);
    try {
      // Try to open with the dedicated app if installed
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        // If external app launch returns false, try Chrome specifically
        final chromeUri = Uri.parse('googlechrome://navigate?url=$url');
        if (await canLaunchUrl(chromeUri)) {
          await launchUrl(chromeUri, mode: LaunchMode.externalApplication);
        } else {
          // Final fallback to default browser
          await launchUrl(uri, mode: LaunchMode.platformDefault);
        }
      }
    } catch (e) {
      try {
        final chromeUri = Uri.parse('googlechrome://navigate?url=$url');
        if (await canLaunchUrl(chromeUri)) {
          await launchUrl(chromeUri, mode: LaunchMode.externalApplication);
        } else {
          await launchUrl(uri, mode: LaunchMode.platformDefault);
        }
      } catch (e2) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Could not open link')));
        }
      }
    }
  }

  static String getDomainFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final domain = uri.host;

      // Remove 'www.' if present
      if (domain.startsWith('www.')) {
        return domain.substring(4);
      }
      return domain;
    } catch (e) {
      return 'Link';
    }
  }

  /// Extract path or meaningful part from URL for better title
  static String getTitleFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final domain = uri.host;

      // Remove 'www.' if present
      String displayDomain = domain.startsWith('www.')
          ? domain.substring(4)
          : domain;

      // If there's a path, add first segment to make it more meaningful
      if (uri.path.isNotEmpty && uri.path != '/') {
        final pathSegments = uri.pathSegments
            .where((s) => s.isNotEmpty)
            .toList();
        if (pathSegments.isNotEmpty) {
          final firstSegment = pathSegments.first;
          // Capitalize and clean up
          final cleanedSegment = firstSegment
              .replaceAll('-', ' ')
              .replaceAll('_', ' ');
          return '$displayDomain · ${cleanedSegment.substring(0, 1).toUpperCase()}${cleanedSegment.substring(1)}';
        }
      }

      return displayDomain;
    } catch (e) {
      return url.length > 50 ? '${url.substring(0, 50)}...' : url;
    }
  }

  /// Format timestamp to a readable string
  static String formatTimestamp(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      // Format as "Jan 17, 2025"
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      final month = months[dateTime.month - 1];
      return '$month ${dateTime.day}, ${dateTime.year}';
    }
  }

  /// Truncate URL for display
  static String truncateUrl(String url, {int maxLength = 40}) {
    if (url.length <= maxLength) {
      return url;
    }
    return '${url.substring(0, maxLength)}...';
  }
}
