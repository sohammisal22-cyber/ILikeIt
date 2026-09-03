import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class UserSessionManager {
  static const _storage = FlutterSecureStorage();
  static const _channel = MethodChannel('shared_link');
  static const _keyUserId = 'user_id';
  static const _keyEmail = 'email';
  static const _keyUsername = 'username';
  static const _keyMobile = 'mobile_number';
  static const _keyIsBackedUp = 'is_backed_up';
  static const _keyHasCreatedFolder = 'has_created_folder';

  static String? _currentUserId;
  static String? _currentEmail;
  static String? _currentUsername;
  static String? _currentMobile;
  static bool _hasCreatedFolder = false;

  static String get userId => _currentUserId!;
  static String? get email => _currentEmail;
  static String? get username => _currentUsername;
  static String? get mobile => _currentMobile;
  static bool get hasCreatedFolder => _hasCreatedFolder;

  static Future<void> _notifyNativeAuthState(bool isLoggedIn) async {
    try {
      if (Platform.isIOS) {
        if (isLoggedIn) {
          await _channel.invokeMethod('setAuthState', true);
        } else {
          await _channel.invokeMethod('clearUserData');
        }
      }
    } catch (e) {
      debugPrint("[DEV] UserSessionManager: Failed to notify native auth state: $e");
    }
  }

  /// Initialize session: recover existing ID, Email, Username, Mobile
  static Future<void> initialize() async {
    try {
      String? storedId = await _storage.read(key: _keyUserId);
      String? storedHasCreated = await _storage.read(key: _keyHasCreatedFolder);
      _hasCreatedFolder = storedHasCreated == 'true';

      if (storedId != null) {
        _currentUserId = storedId;
        _currentEmail = await _storage.read(key: _keyEmail);
        _currentUsername = await _storage.read(key: _keyUsername);
        _currentMobile = await _storage.read(key: _keyMobile);
        _notifyNativeAuthState(true);
        assert(() { debugPrint("[DEV] UserSessionManager: Initialized. User ID present: ${_currentUserId != null}"); return true; }());
      } else {
        _notifyNativeAuthState(false);
        assert(() { debugPrint("[DEV] UserSessionManager: Fresh app state."); return true; }());
      }
    } catch (e) {
      assert(() { debugPrint("[DEV] UserSessionManager: Error initializing session: $e"); return true; }());
    }
  }

  /// Track when user creates a folder
  static Future<void> setHasCreatedFolder(bool value) async {
    _hasCreatedFolder = value;
    await _storage.write(key: _keyHasCreatedFolder, value: value.toString());
  }

  /// Check if the user is fully logged in
  static Future<bool> isBackedUp() async {
    final val = await _storage.read(key: _keyIsBackedUp);
    return val == 'true';
  }

  /// Login: Save the Session
  static Future<void> loginWithEmail(String newUserId, String newEmail) async {
    await _storage.write(key: _keyUserId, value: newUserId);
    await _storage.write(key: _keyEmail, value: newEmail);
    await _storage.write(key: _keyIsBackedUp, value: 'true'); // Is logged in

    _currentUserId = newUserId;
    _currentEmail = newEmail;
    await _notifyNativeAuthState(true);
  }

  /// Save/Update User Profile details locally
  static Future<void> saveUserProfile(String newUsername, String newMobile) async {
    await _storage.write(key: _keyUsername, value: newUsername);
    await _storage.write(key: _keyMobile, value: newMobile);

    _currentUsername = newUsername;
    _currentMobile = newMobile;
  }

  /// Logout: Clear all session data
  static Future<void> clearSession() async {
    await _storage.delete(key: _keyUserId);
    await _storage.delete(key: _keyEmail);
    await _storage.delete(key: _keyUsername);
    await _storage.delete(key: _keyMobile);
    await _storage.delete(key: _keyIsBackedUp);
    await _storage.delete(key: _keyHasCreatedFolder);

    _currentUserId = null;
    _currentEmail = null;
    _currentUsername = null;
    _currentMobile = null;
    _hasCreatedFolder = false;
    await _notifyNativeAuthState(false);
    assert(() { debugPrint("[DEV] UserSessionManager: Session cleared."); return true; }());
  }
}
