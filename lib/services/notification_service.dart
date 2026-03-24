import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();

  static final _plugin = FlutterLocalNotificationsPlugin();

  static const _channelCalls = 'the_thai_calls';
  static const _channelPost = 'the_thai_post_call';
  static const _idIncoming = 1;
  static const _idPostCall = 2;

  /// [onResponse]: actionId가 null이면 알림 본문 탭, 'yes'/'no'이면 액션 탭
  static Future<void> initialize(
      void Function(String? actionId) onResponse) async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: (r) {
        final actionId =
            r.notificationResponseType ==
                    NotificationResponseType.selectedNotificationAction
                ? r.actionId
                : null;
        onResponse(actionId);
      },
    );

    final android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await android?.createNotificationChannel(AndroidNotificationChannel(
      _channelCalls,
      '수신 전화',
      description: '전화 수신 시 표시되는 알림',
      importance: Importance.max,
      playSound: false,
      vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
    ));

    await android?.createNotificationChannel(const AndroidNotificationChannel(
      _channelPost,
      '통화 후 알림',
      description: '통화 종료 후 예약 확인 알림',
      importance: Importance.high,
    ));
  }

  /// 전화 수신 중 알림 (ongoing)
  static Future<void> showIncomingCall({
    required String title,
    required String body,
  }) async {
    await _plugin.show(
      _idIncoming,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelCalls,
          '수신 전화',
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.call,
          ongoing: true,
          autoCancel: false,
        ),
      ),
    );
  }

  /// 통화 종료 후 예약 확인 알림
  ///
  /// 액션 버튼 없이 알림 본문 탭만 사용.
  /// 이유: flutter_local_notifications 액션 버튼은 백그라운드에서
  /// 별도 Dart isolate(onDidReceiveBackgroundNotificationResponse)가 필요하여
  /// 메인 isolate와 통신이 복잡함. 본문 탭은 onDidReceiveNotificationResponse
  /// (메인 isolate)에서 처리되므로 안정적.
  /// 킬드 상태의 native 알림(PhoneStateReceiver.kt)은 여전히 [예][아니오] 버튼 지원.
  static Future<void> showPostCall({
    required String title,
    required String body,
  }) async {
    await _plugin.show(
      _idPostCall,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelPost,
          '통화 후 알림',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  static Future<void> cancelIncoming() => _plugin.cancel(_idIncoming);
  static Future<void> cancelPostCall() => _plugin.cancel(_idPostCall);
  static Future<void> cancelAll() => _plugin.cancelAll();
}
