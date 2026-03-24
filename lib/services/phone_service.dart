import 'dart:async';
import 'package:phone_state/phone_state.dart';
import 'package:permission_handler/permission_handler.dart';

enum PhoneCallEventType { incoming, ended }

class PhoneCallEvent {
  final PhoneCallEventType type;
  final String? phoneNumber; // digits only, e.g. "01012345678"

  const PhoneCallEvent({required this.type, this.phoneNumber});
}

class PhoneService {
  PhoneService._internal();
  static final PhoneService instance = PhoneService._internal();

  final _controller = StreamController<PhoneCallEvent>.broadcast();
  Stream<PhoneCallEvent> get events => _controller.stream;

  StreamSubscription? _sub;
  String? _lastIncomingNumber;
  bool _permissionGranted = false;

  Future<bool> initialize() async {
    final status = await Permission.phone.request();
    _permissionGranted = status.isGranted;
    if (!_permissionGranted) return false;

    _sub = PhoneState.stream.listen(_onState);
    return true;
  }

  void _onState(PhoneState state) {
    switch (state.status) {
      case PhoneStateStatus.CALL_INCOMING:
        _lastIncomingNumber = normalize(state.number);
        _controller.add(PhoneCallEvent(
          type: PhoneCallEventType.incoming,
          phoneNumber: _lastIncomingNumber,
        ));
        break;

      case PhoneStateStatus.CALL_ENDED:
        if (_lastIncomingNumber != null) {
          _controller.add(PhoneCallEvent(
            type: PhoneCallEventType.ended,
            phoneNumber: _lastIncomingNumber,
          ));
          _lastIncomingNumber = null;
        }
        break;

      case PhoneStateStatus.NOTHING:
        _lastIncomingNumber = null;
        break;

      default:
        break;
    }
  }

  /// 전화번호를 숫자만 남기고 정규화 (국제전화 접두사 처리)
  ///
  /// 케이스:
  ///   +82-10-1234-5678  → digits 821012345678 (12자리) → 01012345678
  ///   +82-010-1234-5678 → digits 8201012345678 (13자리) → 01012345678
  ///   010-1234-5678     → digits 01012345678 (그대로)
  static String? normalize(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    String digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('82')) {
      final withoutCode = digits.substring(2);
      // withoutCode가 이미 0으로 시작 → 82-010-... 형식 (그냥 0 제거)
      // withoutCode가 0으로 시작 안 함 → 82-10-... 형식 (0 추가)
      digits = withoutCode.startsWith('0') ? withoutCode : '0$withoutCode';
    }
    return digits.isEmpty ? null : digits;
  }

  /// 숫자 번호를 표시용 형식으로 변환 (01012345678 → 010-1234-5678)
  static String format(String digits) {
    if (digits.length == 11) {
      return '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7)}';
    } else if (digits.length == 10) {
      return '${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6)}';
    }
    return digits;
  }

  void dispose() {
    _sub?.cancel();
    _controller.close();
  }
}
