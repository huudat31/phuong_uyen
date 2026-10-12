import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class MonitorService {
  static const MethodChannel _channel = MethodChannel(
    'self_monitor_app/native',
  );

  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  static Future<bool> isAccessibilityServiceEnabled() async {
    if (!isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>(
        'isAccessibilityServiceEnabled',
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openAccessibilitySettings() async {
    if (!isAndroid) return;
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } catch (_) {}
  }

  static Future<bool> requestScreenCapturePermission() async {
    if (!isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>(
        'requestScreenCapturePermission',
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> startScreenshotService({int intervalSeconds = 30}) async {
    if (!isAndroid) return;
    try {
      await _channel.invokeMethod('startScreenshotService', {
        'intervalSeconds': intervalSeconds,
      });
    } catch (_) {}
  }

  static Future<void> stopScreenshotService() async {
    if (!isAndroid) return;
    try {
      await _channel.invokeMethod('stopScreenshotService');
    } catch (_) {}
  }

  static Future<bool> isScreenshotServiceRunning() async {
    if (!isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>(
        'isScreenshotServiceRunning',
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>(
        'isIgnoringBatteryOptimizations',
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestIgnoreBatteryOptimizations() async {
    if (!isAndroid) return;
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (_) {}
  }

  /// Lưu cấu hình Telegram (Token, Chat ID, Bật/Tắt) xuống native để background service sử dụng
  static Future<bool> saveTelegramConfig({
    required String botToken,
    required String chatId,
    required bool enabled,
  }) async {
    if (!isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>('saveTelegramConfig', {
        'botToken': botToken,
        'chatId': chatId,
        'enabled': enabled,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> getTelegramConfig() async {
    if (!isAndroid) return {'botToken': '', 'chatId': '', 'enabled': false};
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'getTelegramConfig',
      );
      return res ?? {'botToken': '', 'chatId': '', 'enabled': false};
    } catch (_) {
      return {'botToken': '', 'chatId': '', 'enabled': false};
    }
  }

  static Future<Map<String, dynamic>> testTelegramConnection({
    required String botToken,
    required String chatId,
  }) async {
    if (!isAndroid) {
      return {'success': false, 'message': 'Chỉ hỗ trợ trên Android'};
    }
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'testTelegramConnection',
        {'botToken': botToken, 'chatId': chatId},
      );
      return res ??
          {'success': false, 'message': 'Không có phản hồi từ máy chủ'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> syncTelegramNow() async {
    if (!isAndroid) return {'sentTexts': 0, 'sentPhotos': 0, 'error': ''};
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'syncTelegramNow',
      );
      return res ?? {'sentTexts': 0, 'sentPhotos': 0, 'error': ''};
    } catch (e) {
      return {'sentTexts': 0, 'sentPhotos': 0, 'error': e.toString()};
    }
  }

  static Future<Map<String, int>> getDatabaseStats() async {
    if (!isAndroid) return {'textCount': 0, 'screenshotCount': 0};
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'getDatabaseStats',
      );
      return {
        'textCount': (res?['textCount'] as int?) ?? 0,
        'screenshotCount': (res?['screenshotCount'] as int?) ?? 0,
      };
    } catch (_) {
      return {'textCount': 0, 'screenshotCount': 0};
    }
  }
}
