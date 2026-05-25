import 'package:flutter/foundation.dart';

class AppLogger {
  static void log(String scope, String message) {
    if (!kDebugMode) return;
    debugPrint('[$scope] $message');
  }
}
