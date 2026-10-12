import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Lớp giao tiếp với code native Android (Kotlin) qua Platform Channel.
/// Toàn bộ logic AccessibilityService nằm ở phía native,
/// Dart chỉ gọi lệnh kiểm tra và mở cài đặt.
class MonitorService {
  static const MethodChannel _channel =
      MethodChannel('self_monitor_app/native');

  /// Kiểm tra có đang chạy trên Android hay không
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  /// Kiểm tra xem Accessibility Service của app đã được bật trong
  /// Settings > Accessibility chưa.
  static Future<bool> isAccessibilityServiceEnabled() async {
    if (!isAndroid) return false;
    try {
      final result =
          await _channel.invokeMethod<bool>('isAccessibilityServiceEnabled');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Mở màn hình Settings > Accessibility để người dùng tự bật/tắt dịch vụ.
  /// Android không cho phép app tự bật Accessibility bằng code vì lý do
  /// bảo mật — người dùng luôn phải thao tác thủ công 1 lần.
  static Future<void> openAccessibilitySettings() async {
    if (!isAndroid) return;
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } catch (_) {}
  }

  /// Kiểm tra xem app đã được miễn trừ tối ưu hoá pin (Battery Optimization) chưa.
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!isAndroid) return false;
    try {
      final result =
          await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Yêu cầu người dùng bỏ qua tối ưu hoá pin để app chạy ngầm không bị hệ thống kill.
  static Future<void> requestIgnoreBatteryOptimizations() async {
    if (!isAndroid) return;
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (_) {}
  }
}
