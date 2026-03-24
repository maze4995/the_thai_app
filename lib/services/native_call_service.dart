import 'package:flutter/services.dart';

/// 네이티브(Kotlin) SharedPreferences와 통신하는 서비스.
/// 앱이 완전히 종료된 상태에서 수신된 전화 정보를 읽어온다.
class NativeCallService {
  static const _channel = MethodChannel('com.example.the_thai/native_call');

  /// 킬드 상태에서 수신된 전화 정보 조회.
  /// 반환값: { 'number': '01012345678', 'state': 'incoming'|'ended', 'action': ''|'view_card' }
  /// 대기 중인 정보가 없으면 null.
  static Future<Map<String, String>?> getPendingCall() async {
    try {
      final result =
          await _channel.invokeMethod<Map<Object?, Object?>>('getPendingCall');
      if (result == null) return null;
      return {
        'number': (result['number'] as String?) ?? '',
        'state': (result['state'] as String?) ?? '',
        'action': (result['action'] as String?) ?? '',
      };
    } catch (_) {
      return null;
    }
  }

  /// 처리 완료 후 네이티브 상태 초기화
  static Future<void> clearPendingCall() async {
    try {
      await _channel.invokeMethod('clearPendingCall');
    } catch (_) {}
  }
}
