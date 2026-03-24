class VisitHistory {
  final String id;
  final String customerId;
  final DateTime visitDate;
  final String visitType; // '주간' or '야간'
  final String serviceName;
  final int servicePrice;
  final DateTime createdAt;

  VisitHistory({
    required this.id,
    required this.customerId,
    required this.visitDate,
    required this.visitType,
    required this.serviceName,
    required this.servicePrice,
    required this.createdAt,
  });

  factory VisitHistory.fromJson(Map<String, dynamic> json) {
    return VisitHistory(
      id: json['id'] as String,
      customerId: json['customer_id'] as String,
      visitDate: DateTime.parse(json['visit_date'] as String),
      visitType: json['visit_type'] as String? ?? '주간',
      serviceName: json['service_name'] as String? ?? '',
      servicePrice: json['service_price'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
