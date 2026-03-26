import '../app_config.dart';
import '../services/auth_service.dart';

class Customer {
  final String id;
  final String name;
  final String phone;
  final String memberType;
  final String? customerSource;
  final int visitCount;
  final int dayVisitCount;
  final int nightVisitCount;
  final DateTime? lastVisitDate;
  final int couponBalance;
  final String? memo;
  final DateTime createdAt;

  Customer({
    required this.id,
    required this.name,
    required this.phone,
    required this.memberType,
    this.customerSource,
    required this.visitCount,
    required this.dayVisitCount,
    required this.nightVisitCount,
    this.lastVisitDate,
    required this.couponBalance,
    this.memo,
    required this.createdAt,
  });

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String,
      memberType: json['member_type'] as String? ?? '\uB85C\uB4DC\uD68C\uC6D0',
      customerSource: json['customer_source'] as String?,
      visitCount: json['visit_count'] as int? ?? 0,
      dayVisitCount: json['day_visit_count'] as int? ?? 0,
      nightVisitCount: json['night_visit_count'] as int? ?? 0,
      lastVisitDate: json['last_visit_date'] != null
          ? DateTime.parse(json['last_visit_date'] as String)
          : null,
      couponBalance: json['coupon_balance'] as int? ?? 0,
      memo: json['memo'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'phone': phone,
      'member_type': memberType,
      'customer_source': customerSource,
      'visit_count': visitCount,
      'last_visit_date': lastVisitDate?.toIso8601String().split('T').first,
      'coupon_balance': couponBalance,
      'memo': memo,
    };
  }

  Customer copyWith({
    String? name,
    String? phone,
    String? memberType,
    String? customerSource,
    int? visitCount,
    int? dayVisitCount,
    int? nightVisitCount,
    DateTime? lastVisitDate,
    int? couponBalance,
    String? memo,
  }) {
    return Customer(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      memberType: memberType ?? this.memberType,
      customerSource: customerSource ?? this.customerSource,
      visitCount: visitCount ?? this.visitCount,
      dayVisitCount: dayVisitCount ?? this.dayVisitCount,
      nightVisitCount: nightVisitCount ?? this.nightVisitCount,
      lastVisitDate: lastVisitDate ?? this.lastVisitDate,
      couponBalance: couponBalance ?? this.couponBalance,
      memo: memo ?? this.memo,
      createdAt: createdAt,
    );
  }

  String get visitGrade {
    final count = effectiveVisitCount;
    if (count <= 1) return 'New';
    if (count <= 4) return 'N';
    if (count <= 9) return 'S';
    if (count <= 19) return 'G';
    if (count <= 49) return 'V';
    return 'VV';
  }

  int get effectiveVisitCount {
    final combined = dayVisitCount + nightVisitCount;
    return combined > visitCount ? combined : visitCount;
  }

  String get effectiveSource {
    if (customerSource != null && customerSource!.isNotEmpty) {
      return customerSource!;
    }
    return memberType == '\uB85C\uB4DC\uD68C\uC6D0'
        ? '\uB85C\uB4DC'
        : '\uAE30\uC874';
  }

  String get phoneLastFour {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 4) return digits;
    return digits.substring(digits.length - 4);
  }

  static String buildContactLabel({
    required String phone,
    required String source,
    required int visitCount,
    required int dayVisitCount,
    required int nightVisitCount,
    int couponBalance = 0,
    String? memo,
  }) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final suffix =
        digits.length >= 4 ? digits.substring(digits.length - 4) : digits;
    final grade = switch (visitCount) {
      <= 1 => 'New',
      <= 4 => 'N',
      <= 9 => 'S',
      <= 19 => 'G',
      <= 49 => 'V',
      _ => 'VV',
    };
    final special = couponBalance > 0 ? ',스페셜' : '';
    final memoSuffix =
        (memo != null && memo.isNotEmpty) ? ',$memo' : '';
    final prefix = AuthService.storeName ?? AppConfig.contactPrefix;
    return '$prefix-$grade-$source$special$memoSuffix($dayVisitCount)($nightVisitCount)$suffix';
  }

  String get contactLabel {
    return buildContactLabel(
      phone: phone,
      source: effectiveSource,
      visitCount: effectiveVisitCount,
      dayVisitCount: dayVisitCount,
      nightVisitCount: nightVisitCount,
      couponBalance: couponBalance,
      memo: memo,
    );
  }
}
