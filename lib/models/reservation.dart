class Reservation {
  final String id;
  final String? customerId;
  final String customerName;
  final String customerPhone;
  final DateTime reservedDate;
  final String reservedTime;
  final String? serviceName;
  final String source;
  final String status;
  final String? memo;
  final int couponUsed;
  final DateTime createdAt;

  const Reservation({
    required this.id,
    this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.reservedDate,
    required this.reservedTime,
    this.serviceName,
    required this.source,
    required this.status,
    this.memo,
    required this.couponUsed,
    required this.createdAt,
  });

  factory Reservation.fromJson(Map<String, dynamic> json) {
    final timeStr = json['reserved_time'] as String;
    return Reservation(
      id: json['id'] as String,
      customerId: json['customer_id'] as String?,
      customerName: json['customer_name'] as String,
      customerPhone: json['customer_phone'] as String,
      reservedDate: DateTime.parse(json['reserved_date'] as String),
      reservedTime: timeStr.length >= 5 ? timeStr.substring(0, 5) : timeStr,
      serviceName: json['service_name'] as String?,
      source: json['source'] as String? ?? '기존',
      status: json['status'] as String? ?? '예약확정',
      memo: json['memo'] as String?,
      couponUsed: json['coupon_used'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
