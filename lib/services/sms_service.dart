import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

class SmsService {
  static const _channel = MethodChannel('com.example.the_thai/native_call');

  static const defaultTemplate =
      '\u25C7\uAC15\uC11C\uB354\uD0C0\uC774 \uC2E0\uB144\uB9DE\uC774 \uB300\uBC15 \uCFE0\uD3F0\uD329\u25C7\n\n[M/d] [service] \uC0AC\uC6A9, \uCFE0\uD3F0 \uC794\uC561 : [remaining]\uC6D0\n\uAC10\uC0AC\uD569\uB2C8\uB2E4~^^';

  static const depletionTemplate =
      '\u25C7\uAC15\uC11C\uB354\uD0C0\uC774 \uC2E0\uB144\uB9DE\uC774 \uB300\uBC15 \uCFE0\uD3F0\uD329\u25C7\n\n[M/d] [service]\uC0AC\uC6A9, \uCFE0\uD3F0\uC744 \uBAA8\uB450\n\uC0AC\uC6A9\uD558\uC168\uC2B5\uB2C8\uB2E4. \uC9C0\uAE08 \uC9C4\uD589\uD558\uB294 \uC774\uBCA4\uD2B8\uAC00 \uC774\uBC88\uB2EC\uC5D0 \uC885\uB8CC\uD558\uB2C8\n\uCC38\uACE0\uD574\uC8FC\uC138\uC694~\n\uAC10\uC0AC\uD569\uB2C8\uB2E4~^^';

  static const _serviceAbbr = {
    '\uD0C0\uC774 60\uBD84': 'T60',
    '\uD0C0\uC774 90\uBD84': 'T90',
    '\uC544\uB85C\uB9C8 60\uBD84': 'A60',
    '\uC544\uB85C\uB9C8 90\uBD84': 'A90',
    '\uD06C\uB9BC 60\uBD84': 'C60',
    '\uD06C\uB9BC 90\uBD84': 'C90',
    '\uC2A4\uC6E8\uB514\uC2DC 60\uBD84': 'S60',
    '\uC2A4\uC6E8\uB514\uC2DC 90\uBD84': 'S90',
  };

  static Future<String> getTemplate() async {
    try {
      final result = await _channel.invokeMethod<String>('getSmsTemplate');
      return result ?? defaultTemplate;
    } catch (_) {
      return defaultTemplate;
    }
  }

  static Future<void> saveTemplate(String template) async {
    await _channel.invokeMethod<void>('setSmsTemplate', {'template': template});
  }

  static Future<String> getDepletionTemplate() async {
    try {
      final result =
          await _channel.invokeMethod<String>('getSmsDepletionTemplate');
      return result ?? depletionTemplate;
    } catch (_) {
      return depletionTemplate;
    }
  }

  static Future<void> saveDepletionTemplate(String template) async {
    await _channel.invokeMethod<void>(
      'setSmsDepletionTemplate',
      {'template': template},
    );
  }

  static String _buildMessage({
    required String template,
    required String serviceName,
    required int remaining,
  }) {
    final abbr = _serviceAbbr[serviceName] ?? serviceName;
    final now = DateTime.now();
    final dateStr = '${now.month}/${now.day}';
    final remainingStr = NumberFormat('#,###', 'ko_KR').format(remaining);

    return template
        .replaceAll('[M/d]', dateStr)
        .replaceAll('[service]', abbr)
        .replaceAll('[\uC57D\uC5B4]', abbr)
        .replaceAll('[\uC601\uC5B4]', abbr)
        .replaceAll('[remaining]', remainingStr);
  }

  static Future<bool> sendCouponDeductionMessage({
    required String phone,
    required String serviceName,
    required int remaining,
    required bool usedAllCoupons,
  }) async {
    try {
      final status = await Permission.sms.request();
      if (!status.isGranted) return false;

      final template = usedAllCoupons
          ? await getDepletionTemplate()
          : await getTemplate();
      final message = _buildMessage(
        template: template,
        serviceName: serviceName,
        remaining: remaining,
      );
      final normalizedPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');

      await _channel.invokeMethod<void>('sendSms', {
        'phone': normalizedPhone,
        'message': message,
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}
