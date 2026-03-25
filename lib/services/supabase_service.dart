import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/service_menu.dart';
import '../models/customer.dart';
import '../models/reservation.dart';
import '../models/visit_history.dart';
import 'auth_service.dart';

class SupabaseService {
  static SupabaseClient get _client => Supabase.instance.client;

  static String _normalizePhone(String value) {
    String digits = value.replaceAll(RegExp(r'\D'), '');
    // +82-10-xxxx-xxxx 형식 → 010xxxxxxxx 변환
    if (digits.startsWith('82') && digits.length > 10) {
      final without = digits.substring(2);
      digits = without.startsWith('0') ? without : '0$without';
    }
    return digits;
  }

  static String _formatPhone(String digits) {
    if (digits.length == 11) {
      return '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7)}';
    }
    if (digits.length == 10) {
      return '${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6)}';
    }
    return digits;
  }

  static String _sourceFromCustomerRow(Map<String, dynamic> row) {
    return row['customer_source'] as String? ??
        ((row['member_type'] as String? ?? '\uB85C\uB4DC\uD68C\uC6D0') ==
                '\uB85C\uB4DC\uD68C\uC6D0'
            ? '\uB85C\uB4DC'
            : '\uAE30\uC874');
  }

  static String _visitTypeFromHour(int hour) {
    return (hour >= 6 && hour < 18) ? '\uC8FC\uAC04' : '\uC57C\uAC04';
  }

  static String _visitTypeFromTime(String reservedTime) {
    final hour = int.tryParse(reservedTime.split(':').first) ?? 0;
    return _visitTypeFromHour(hour);
  }


  Future<Customer> _updateCustomerVisitSnapshot({
    required String customerId,
    required int visitCount,
    required int dayVisitCount,
    required int nightVisitCount,
    DateTime? lastVisitDate,
    int couponToRestore = 0,
  }) async {
    final current = await _client
        .from('customers')
        .select('phone, member_type, customer_source, coupon_balance')
        .eq('id', customerId)
        .single();

    final currentBalance = (current['coupon_balance'] as int?) ?? 0;
    final newBalance = couponToRestore > 0 ? currentBalance + couponToRestore : currentBalance;
    final payload = <String, dynamic>{
      'name': Customer.buildContactLabel(
        phone: current['phone'] as String,
        source: _sourceFromCustomerRow(current),
        visitCount: visitCount,
        dayVisitCount: dayVisitCount,
        nightVisitCount: nightVisitCount,
        couponBalance: newBalance,
      ),
      'visit_count': visitCount,
      'day_visit_count': dayVisitCount,
      'night_visit_count': nightVisitCount,
    };
    if (lastVisitDate != null) {
      payload['last_visit_date'] =
          lastVisitDate.toIso8601String().split('T').first;
    }
    if (couponToRestore > 0) {
      payload['coupon_balance'] = newBalance;
    }

    final response = await _client
        .from('customers')
        .update(payload)
        .eq('id', customerId)
        .select()
        .single();
    return Customer.fromJson(response);
  }

  Future<void> _insertReservationVisitHistory({
    required String customerId,
    required DateTime reservedDate,
    required String reservedTime,
    required String? serviceName,
  }) async {
    await _client.from('visit_history').insert({
      'customer_id': customerId,
      'visit_date': reservedDate.toIso8601String().split('T').first,
      'visit_type': _visitTypeFromTime(reservedTime),
      'service_name': serviceName ?? '\uC608\uC57D\uD655\uC815',
      'service_price': 0,
      if (AuthService.storeId != null) 'store_id': AuthService.storeId,
    });
  }

  Future<void> _deleteReservationVisitHistory({
    required String customerId,
    required DateTime reservedDate,
    required String reservedTime,
    required String? serviceName,
  }) async {
    final visitType = _visitTypeFromTime(reservedTime);
    final visitDate = reservedDate.toIso8601String().split('T').first;
    final targetServiceName = serviceName ?? '\uC608\uC57D\uD655\uC815';

    final response = await _client
        .from('visit_history')
        .select('id')
        .eq('customer_id', customerId)
        .eq('visit_date', visitDate)
        .eq('visit_type', visitType)
        .eq('service_name', targetServiceName)
        .order('created_at', ascending: false)
        .limit(1);

    final rows = response as List;
    if (rows.isEmpty) return;

    await _client
        .from('visit_history')
        .delete()
        .eq('id', rows.first['id'] as String);
  }

  Future<Customer?> _rollbackReservationEffect({
    required String customerId,
    required DateTime reservedDate,
    required String reservedTime,
    required String? serviceName,
    int couponToRestore = 0,
  }) async {
    final customer = await _client
        .from('customers')
        .select('visit_count, day_visit_count, night_visit_count')
        .eq('id', customerId)
        .single();

    final isDayVisit = _visitTypeFromTime(reservedTime) == '\uC8FC\uAC04';
    final nextVisitCount = ((customer['visit_count'] as int?) ?? 0) - 1;
    final nextDayVisitCount =
        ((customer['day_visit_count'] as int?) ?? 0) - (isDayVisit ? 1 : 0);
    final nextNightVisitCount =
        ((customer['night_visit_count'] as int?) ?? 0) - (isDayVisit ? 0 : 1);

    await _deleteReservationVisitHistory(
      customerId: customerId,
      reservedDate: reservedDate,
      reservedTime: reservedTime,
      serviceName: serviceName,
    );

    return _updateCustomerVisitSnapshot(
      customerId: customerId,
      visitCount: nextVisitCount < 0 ? 0 : nextVisitCount,
      dayVisitCount: nextDayVisitCount < 0 ? 0 : nextDayVisitCount,
      nightVisitCount: nextNightVisitCount < 0 ? 0 : nextNightVisitCount,
      couponToRestore: couponToRestore,
    );
  }

  Future<List<Customer>> getCustomers() async {
    final customers = <Customer>[];
    const pageSize = 1000;
    var offset = 0;
    while (true) {
      final response = await _client
          .from('customers')
          .select()
          .order('name', ascending: true)
          .range(offset, offset + pageSize - 1);
      final page = response as List;
      for (final e in page) {
        try {
          customers.add(Customer.fromJson(e as Map<String, dynamic>));
        } catch (_) {
          // 파싱 실패 행은 건너뜀 (나머지 고객 목록은 정상 표시)
        }
      }
      if (page.length < pageSize) break;
      offset += pageSize;
    }
    return customers;
  }

  Future<List<Customer>> getCouponCustomers() async {
    // 서버에서 coupon_balance > 0 인 고객만 조회 (전체 로드 불필요)
    final customers = <Customer>[];
    const pageSize = 1000;
    var offset = 0;
    while (true) {
      final response = await _client
          .from('customers')
          .select()
          .gt('coupon_balance', 0)
          .order('name', ascending: true)
          .range(offset, offset + pageSize - 1);
      final page = response as List;
      for (final e in page) {
        try {
          customers.add(Customer.fromJson(e as Map<String, dynamic>));
        } catch (_) {}
      }
      if (page.length < pageSize) break;
      offset += pageSize;
    }
    return customers;
  }

  /// 이름/전화번호 검색용 OR 필터 문자열을 생성합니다.
  /// 전화번호가 DB에 대시 포함(010-1234-5678) 또는 숫자만(01012345678) 저장된
  /// 두 가지 형식 모두를 커버합니다.
  static String _buildSearchFilter(String trimmed) {
    final filters = <String>['name.ilike.%$trimmed%'];

    final digits = _normalizePhone(trimmed);
    if (digits.length >= 4) {
      // 숫자만 저장된 경우 매칭
      filters.add('phone.ilike.%$digits%');

      // 대시 포함 형식으로 저장된 경우 매칭 (11자리: 010-1234-5678)
      final formatted = _formatPhone(digits);
      if (formatted != digits) {
        filters.add('phone.ilike.%$formatted%');
      }

      // 8자리 입력(예: 12345678) → "1234-5678" 패턴으로도 검색
      // DB에 010-1234-5678 형태로 저장된 경우 12345678 검색이 안 되는 문제 해결
      if (digits.length == 8) {
        final mid = '${digits.substring(0, 4)}-${digits.substring(4)}';
        filters.add('phone.ilike.%$mid%');
      }
    }

    return filters.join(',');
  }

  Future<Map<String, Customer>> getCustomerPhoneIndex() async {
    final allCustomers = await getCustomers();
    return {
      for (final customer in allCustomers) _normalizePhone(customer.phone): customer,
    };
  }

  Future<List<Customer>> searchCustomers(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return getCustomers();

    final filter = _buildSearchFilter(trimmed);

    final response = await _client
        .from('customers')
        .select()
        .or(filter)
        .order('name', ascending: true)
        .limit(500);

    final customers = <Customer>[];
    for (final e in response as List) {
      try {
        customers.add(Customer.fromJson(e as Map<String, dynamic>));
      } catch (_) {}
    }
    return customers;
  }

  Future<List<Customer>> searchCouponCustomers(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return getCouponCustomers();

    final filter = _buildSearchFilter(trimmed);

    final response = await _client
        .from('customers')
        .select()
        .or(filter)
        .gt('coupon_balance', 0)
        .order('name', ascending: true)
        .limit(500);

    final customers = <Customer>[];
    for (final e in response as List) {
      try {
        customers.add(Customer.fromJson(e as Map<String, dynamic>));
      } catch (_) {}
    }
    return customers;
  }

  Future<Customer> addCustomer({
    required String name,
    required String phone,
    required String memberType,
    required String customerSource,
    int visitCount = 0,
    int dayVisitCount = 0,
    int nightVisitCount = 0,
    String? memo,
  }) async {
    final response = await _client
        .from('customers')
        .insert({
          'name': name,
          'phone': phone,
          'member_type': memberType,
          'customer_source': customerSource,
          'visit_count': visitCount,
          'day_visit_count': dayVisitCount,
          'night_visit_count': nightVisitCount,
          'memo': memo,
          if (AuthService.storeId != null) 'store_id': AuthService.storeId,
        })
        .select()
        .single();
    return Customer.fromJson(response);
  }

  Future<void> updateMemo(String customerId, String memo) async {
    await _client.from('customers').update({'memo': memo}).eq('id', customerId);
  }

  Future<void> updatePhone(String customerId, String phone) async {
    await _client.from('customers').update({'phone': phone}).eq('id', customerId);
  }

  Future<Customer> updateCustomerProfile({
    required String customerId,
    required String name,
    required String memberType,
    required String customerSource,
    int? visitCount,
    int? dayVisitCount,
    int? nightVisitCount,
  }) async {
    final updates = <String, dynamic>{
      'name': name,
      'member_type': memberType,
      'customer_source': customerSource,
    };
    if (visitCount != null) updates['visit_count'] = visitCount;
    if (dayVisitCount != null) updates['day_visit_count'] = dayVisitCount;
    if (nightVisitCount != null) updates['night_visit_count'] = nightVisitCount;

    final response = await _client
        .from('customers')
        .update(updates)
        .eq('id', customerId)
        .select()
        .single();
    return Customer.fromJson(response);
  }

  Future<Customer> upsertImportedCustomer({
    required String phone,
    required String customerSource,
    required int visitCount,
    required int dayVisitCount,
    required int nightVisitCount,
    String? memo,
  }) async {
    final existing = await findCustomerByPhone(_normalizePhone(phone));
    final memberType = customerSource == '\uB85C\uB4DC'
        ? '\uB85C\uB4DC\uD68C\uC6D0'
        : '\uC5B4\uD50C\uD68C\uC6D0';

    if (existing == null) {
      return addCustomer(
        name: Customer.buildContactLabel(
          phone: phone,
          source: customerSource,
          visitCount: visitCount,
          dayVisitCount: dayVisitCount,
          nightVisitCount: nightVisitCount,
        ),
        phone: phone,
        memberType: memberType,
        customerSource: customerSource,
        memo: memo,
      );
    }

    final mergedDayVisitCount = dayVisitCount > existing.dayVisitCount
        ? dayVisitCount
        : existing.dayVisitCount;
    final mergedNightVisitCount = nightVisitCount > existing.nightVisitCount
        ? nightVisitCount
        : existing.nightVisitCount;
    final mergedVisitCount = [
      visitCount,
      existing.visitCount,
      mergedDayVisitCount + mergedNightVisitCount,
    ].reduce((a, b) => a > b ? a : b);

    return updateCustomerProfile(
      customerId: existing.id,
      name: Customer.buildContactLabel(
        phone: existing.phone,
        source: customerSource,
        visitCount: mergedVisitCount,
        dayVisitCount: mergedDayVisitCount,
        nightVisitCount: mergedNightVisitCount,
        couponBalance: existing.couponBalance,
      ),
      memberType: memberType,
      customerSource: customerSource,
      visitCount: mergedVisitCount,
      dayVisitCount: mergedDayVisitCount,
      nightVisitCount: mergedNightVisitCount,
    );
  }

  Future<Customer> chargeCoupon(String customerId, int amount) async {
    final current = await _client
        .from('customers')
        .select('coupon_balance')
        .eq('id', customerId)
        .single();
    final response = await _client
        .from('customers')
        .update({'coupon_balance': (current['coupon_balance'] as int) + amount})
        .eq('id', customerId)
        .select()
        .single();
    return Customer.fromJson(response);
  }

  Future<Customer?> findCustomerByPhone(String normalizedPhone) async {
    if (normalizedPhone.isEmpty) return null;
    final formatted = _formatPhone(normalizedPhone);
    final response = await _client
        .from('customers')
        .select()
        .or('phone.eq.$normalizedPhone,phone.eq.$formatted')
        .limit(1);
    if ((response as List).isEmpty) return null;
    return Customer.fromJson(response.first);
  }

  Future<List<VisitHistory>> getVisitHistory(String customerId) async {
    final response = await _client
        .from('visit_history')
        .select()
        .eq('customer_id', customerId)
        .order('visit_date', ascending: false);
    return (response as List).map((e) => VisitHistory.fromJson(e)).toList();
  }

  Future<Customer?> getCustomer(String id) async {
    final response =
        await _client.from('customers').select().eq('id', id).maybeSingle();
    if (response == null) return null;
    return Customer.fromJson(response);
  }

  Future<Customer> addVisit({
    required String customerId,
    required String serviceName,
    required int servicePrice,
    required int amountToDeduct,
  }) async {
    final now = DateTime.now();
    final today = now.toIso8601String().split('T').first;
    final visitType = _visitTypeFromHour(now.hour);

    await _client.from('visit_history').insert({
      'customer_id': customerId,
      'visit_date': today,
      'visit_type': visitType,
      'service_name': serviceName,
      'service_price': servicePrice,
      if (AuthService.storeId != null) 'store_id': AuthService.storeId,
    });

    final current = await _client
        .from('customers')
        .select(
          'phone, member_type, customer_source, visit_count, day_visit_count, night_visit_count, coupon_balance',
        )
        .eq('id', customerId)
        .single();

    final nextVisitCount = (current['visit_count'] as int) + 1;
    final nextDayVisitCount = (current['day_visit_count'] as int) +
        (visitType == '\uC8FC\uAC04' ? 1 : 0);
    final nextNightVisitCount = (current['night_visit_count'] as int) +
        (visitType == '\uC57C\uAC04' ? 1 : 0);

    final nextCouponBalance = (current['coupon_balance'] as int) - amountToDeduct;
    final response = await _client
        .from('customers')
        .update({
          'name': Customer.buildContactLabel(
            phone: current['phone'] as String,
            source: _sourceFromCustomerRow(current),
            visitCount: nextVisitCount,
            dayVisitCount: nextDayVisitCount,
            nightVisitCount: nextNightVisitCount,
            couponBalance: nextCouponBalance,
          ),
          'visit_count': nextVisitCount,
          'day_visit_count': nextDayVisitCount,
          'night_visit_count': nextNightVisitCount,
          'last_visit_date': today,
          'coupon_balance': nextCouponBalance,
        })
        .eq('id', customerId)
        .select()
        .single();
    return Customer.fromJson(response);
  }

  Future<List<Reservation>> getReservationsByDate(DateTime date) async {
    final dateStr = date.toIso8601String().split('T').first;
    final response = await _client
        .from('reservations')
        .select()
        .eq('reserved_date', dateStr)
        .order('reserved_time', ascending: true);
    return (response as List).map((e) => Reservation.fromJson(e)).toList();
  }

  Future<({Customer? customer, int couponDeduct, bool additionalPaymentRequired})> addReservation({
    required String? customerId,
    required String customerName,
    required String customerPhone,
    required DateTime reservedDate,
    required String reservedTime,
    String? serviceName,
    required String source,
    String? memo,
  }) async {
    final dateStr = reservedDate.toIso8601String().split('T').first;

    // 고객 데이터 미리 조회 (쿠폰 차감 계산 포함)
    Map<String, dynamic>? current;
    int couponDeduct = 0;
    var additionalPaymentRequired = false;

    if (customerId != null) {
      current = await _client
          .from('customers')
          .select(
            'phone, member_type, customer_source, visit_count, day_visit_count, night_visit_count, coupon_balance',
          )
          .eq('id', customerId)
          .single();

      if (serviceName != null) {
        final balance = (current['coupon_balance'] as int?) ?? 0;
        if (balance > 0) {
          final memberType =
              current['member_type'] as String? ?? '\uB85C\uB4DC\uD68C\uC6D0';
          final services = kServiceMenu[memberType] ?? <ServiceItem>[];
          ServiceItem? match;
          try {
            match = services.firstWhere((s) => s.name == serviceName);
          } catch (_) {
            match = null;
          }
          if (match != null && match.price > 0) {
            if (match.price > balance) {
              couponDeduct = balance; // cap to balance → 잔액 0원으로
              additionalPaymentRequired = true;
            } else {
              couponDeduct = match.price;
            }
          }
        }
      }
    }

    final insertedReservation = await _client.from('reservations').insert({
      'customer_id': customerId,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'reserved_date': dateStr,
      'reserved_time': '$reservedTime:00',
      'service_name': serviceName,
      'source': source,
      'memo': memo,
      'coupon_used': couponDeduct,
      if (AuthService.storeId != null) 'store_id': AuthService.storeId,
    }).select('id').single();

    if (customerId == null || current == null) {
      return (
        customer: null,
        couponDeduct: 0,
        additionalPaymentRequired: false,
      );
    }

    await _insertReservationVisitHistory(
      customerId: customerId,
      reservedDate: reservedDate,
      reservedTime: reservedTime,
      serviceName: serviceName,
    );

    final isDayVisit = _visitTypeFromTime(reservedTime) == '\uC8FC\uAC04';
    final nextVisitCount = (current['visit_count'] as int) + 1;
    final nextDayVisitCount =
        (current['day_visit_count'] as int) + (isDayVisit ? 1 : 0);
    final nextNightVisitCount =
        (current['night_visit_count'] as int) + (isDayVisit ? 0 : 1);

    final currentBalance = (current['coupon_balance'] as int?) ?? 0;
    final nextCouponBalance = couponDeduct > 0 ? currentBalance - couponDeduct : currentBalance;
    final updatePayload = <String, dynamic>{
      'name': Customer.buildContactLabel(
        phone: current['phone'] as String,
        source: _sourceFromCustomerRow(current),
        visitCount: nextVisitCount,
        dayVisitCount: nextDayVisitCount,
        nightVisitCount: nextNightVisitCount,
        couponBalance: nextCouponBalance,
      ),
      'visit_count': nextVisitCount,
      'day_visit_count': nextDayVisitCount,
      'night_visit_count': nextNightVisitCount,
      'last_visit_date': dateStr,
    };
    if (couponDeduct > 0) {
      updatePayload['coupon_balance'] = nextCouponBalance;
    }

    final response = await _client
        .from('customers')
        .update(updatePayload)
        .eq('id', customerId)
        .select()
        .single();

    // 예약 카드의 고객명을 갱신된 contactLabel로 업데이트
    final updatedCustomer = Customer.fromJson(response);
    await _client.from('reservations').update({
      'customer_name': updatedCustomer.contactLabel,
    }).eq('id', insertedReservation['id'] as String);

    return (
      customer: updatedCustomer,
      couponDeduct: couponDeduct,
      additionalPaymentRequired: additionalPaymentRequired,
    );
  }

  Future<Customer?> updateReservationStatus(
    String id,
    String status, {
    int? couponUsed,
  }) async {
    final reservation = await _client
        .from('reservations')
        .select('customer_id, reserved_date, reserved_time, service_name, status, coupon_used')
        .eq('id', id)
        .single();

    final previousStatus =
        reservation['status'] as String? ?? '\uC608\uC57D\uD655\uC815';
    final update = <String, dynamic>{'status': status};
    if (couponUsed != null) {
      update['coupon_used'] = couponUsed;
    }
    await _client.from('reservations').update(update).eq('id', id);

    final customerId = reservation['customer_id'] as String?;
    if (customerId == null ||
        previousStatus != '\uC608\uC57D\uD655\uC815') {
      return null;
    }

    final reservationCouponUsed = (reservation['coupon_used'] as int?) ?? 0;

    return _rollbackReservationEffect(
      customerId: customerId,
      reservedDate: DateTime.parse(reservation['reserved_date'] as String),
      reservedTime: reservation['reserved_time'] as String? ?? '00:00:00',
      serviceName: reservation['service_name'] as String?,
      couponToRestore: reservationCouponUsed,
    );
  }

  Future<Customer?> deleteReservation(String id) async {
    final reservation = await _client
        .from('reservations')
        .select('customer_id, reserved_date, reserved_time, service_name, status, coupon_used')
        .eq('id', id)
        .single();

    Customer? updatedCustomer;
    final customerId = reservation['customer_id'] as String?;
    final status =
        reservation['status'] as String? ?? '\uC608\uC57D\uD655\uC815';
    if (customerId != null && status == '\uC608\uC57D\uD655\uC815') {
      final reservationCouponUsed = (reservation['coupon_used'] as int?) ?? 0;
      updatedCustomer = await _rollbackReservationEffect(
        customerId: customerId,
        reservedDate: DateTime.parse(reservation['reserved_date'] as String),
        reservedTime: reservation['reserved_time'] as String? ?? '00:00:00',
        serviceName: reservation['service_name'] as String?,
        couponToRestore: reservationCouponUsed,
      );
    }

    await _client.from('reservations').delete().eq('id', id);
    return updatedCustomer;
  }

  Future<void> updateReservation({
    required String reservationId,
    required DateTime reservedDate,
    required String reservedTime,
    String? serviceName,
    required String source,
    String? memo,
  }) async {
    await _client.from('reservations').update({
      'reserved_date': reservedDate.toIso8601String().split('T').first,
      'reserved_time': reservedTime,
      'service_name': serviceName,
      'source': source,
      'memo': memo,
    }).eq('id', reservationId);
  }

  Future<void> deductCouponForNoShow(String customerId, int amount) async {
    final current = await _client
        .from('customers')
        .select('coupon_balance')
        .eq('id', customerId)
        .single();
    await _client.from('customers').update({
      'coupon_balance': (current['coupon_balance'] as int) - amount,
    }).eq('id', customerId);
  }

  Future<List<Customer>> batchAddCustomers(
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return [];
    final storeId = AuthService.storeId;
    final enriched = storeId != null
        ? rows.map((r) => {...r, 'store_id': storeId}).toList()
        : rows;
    final response =
        await _client.from('customers').insert(enriched).select();
    return (response as List).map((e) => Customer.fromJson(e)).toList();
  }

  Future<Customer> updateImportedCustomerFromExisting({
    required Customer existing,
    required String customerSource,
    required int visitCount,
    required int dayVisitCount,
    required int nightVisitCount,
  }) async {
    final memberType =
        customerSource == '\uB85C\uB4DC' ? '\uB85C\uB4DC\uD68C\uC6D0' : '\uC5B4\uD50C\uD68C\uC6D0';
    final mergedDay = dayVisitCount > existing.dayVisitCount
        ? dayVisitCount
        : existing.dayVisitCount;
    final mergedNight = nightVisitCount > existing.nightVisitCount
        ? nightVisitCount
        : existing.nightVisitCount;
    final mergedCount = [
      visitCount,
      existing.visitCount,
      mergedDay + mergedNight,
    ].reduce((a, b) => a > b ? a : b);

    return updateCustomerProfile(
      customerId: existing.id,
      name: Customer.buildContactLabel(
        phone: existing.phone,
        source: customerSource,
        visitCount: mergedCount,
        dayVisitCount: mergedDay,
        nightVisitCount: mergedNight,
        couponBalance: existing.couponBalance,
      ),
      memberType: memberType,
      customerSource: customerSource,
      visitCount: mergedCount,
      dayVisitCount: mergedDay,
      nightVisitCount: mergedNight,
    );
  }

  Future<Customer> deleteVisitHistory({
    required String historyId,
    required String customerId,
    required String visitType,
  }) async {
    await _client.from('visit_history').delete().eq('id', historyId);

    final customer = await _client
        .from('customers')
        .select('visit_count, day_visit_count, night_visit_count')
        .eq('id', customerId)
        .single();

    final isDay = visitType == '\uC8FC\uAC04';
    final nextVisitCount = ((customer['visit_count'] as int?) ?? 0) - 1;
    final nextDayVisitCount =
        ((customer['day_visit_count'] as int?) ?? 0) - (isDay ? 1 : 0);
    final nextNightVisitCount =
        ((customer['night_visit_count'] as int?) ?? 0) - (isDay ? 0 : 1);

    return _updateCustomerVisitSnapshot(
      customerId: customerId,
      visitCount: nextVisitCount < 0 ? 0 : nextVisitCount,
      dayVisitCount: nextDayVisitCount < 0 ? 0 : nextDayVisitCount,
      nightVisitCount: nextNightVisitCount < 0 ? 0 : nextNightVisitCount,
    );
  }

  Future<Customer> updateVisitHistory({
    required String historyId,
    required String customerId,
    required DateTime visitDate,
    required String visitType,
    required String serviceName,
    required int servicePrice,
    required String prevVisitType,
  }) async {
    await _client.from('visit_history').update({
      'visit_date': visitDate.toIso8601String().split('T').first,
      'visit_type': visitType,
      'service_name': serviceName,
      'service_price': servicePrice,
    }).eq('id', historyId);

    if (visitType == prevVisitType) {
      final response = await _client
          .from('customers')
          .select()
          .eq('id', customerId)
          .single();
      return Customer.fromJson(response);
    }

    final customer = await _client
        .from('customers')
        .select('visit_count, day_visit_count, night_visit_count')
        .eq('id', customerId)
        .single();

    final prevIsDay = prevVisitType == '\uC8FC\uAC04';
    final newIsDay = visitType == '\uC8FC\uAC04';
    final nextDayVisitCount =
        ((customer['day_visit_count'] as int?) ?? 0) + (newIsDay ? 1 : 0) - (prevIsDay ? 1 : 0);
    final nextNightVisitCount =
        ((customer['night_visit_count'] as int?) ?? 0) + (newIsDay ? 0 : 1) - (prevIsDay ? 0 : 1);

    return _updateCustomerVisitSnapshot(
      customerId: customerId,
      visitCount: (customer['visit_count'] as int?) ?? 0,
      dayVisitCount: nextDayVisitCount < 0 ? 0 : nextDayVisitCount,
      nightVisitCount: nextNightVisitCount < 0 ? 0 : nextNightVisitCount,
    );
  }

  Future<void> deleteCustomer(String customerId) async {
    await _client
        .from('reservations')
        .update({'customer_id': null})
        .eq('customer_id', customerId);
    await _client.from('visit_history').delete().eq('customer_id', customerId);
    await _client.from('customers').delete().eq('id', customerId);
  }
}
