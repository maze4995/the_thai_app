import 'package:flutter_test/flutter_test.dart';
import 'package:the_thai/models/customer.dart';
import 'package:the_thai/services/contact_sync_service.dart';
import 'package:the_thai/services/phone_service.dart';

void main() {
  group('PhoneService', () {
    test('normalize handles domestic and +82 numbers', () {
      expect(PhoneService.normalize('010-1234-5678'), '01012345678');
      expect(PhoneService.normalize('+82-10-1234-5678'), '01012345678');
      expect(PhoneService.normalize('+82-010-1234-5678'), '01012345678');
    });

    test('format converts digits to dashed number', () {
      expect(PhoneService.format('01012345678'), '010-1234-5678');
      expect(PhoneService.format('0212345678'), '021-234-5678');
    });
  });

  group('Customer', () {
    test('builds unified contact label from visits and source', () {
      final customer = Customer.fromJson({
        'id': 'c1',
        'name': '강서N로드(2)(1)5678',
        'phone': '010-1234-5678',
        'member_type': '로드회원',
        'customer_source': '로드',
        'visit_count': 3,
        'day_visit_count': 2,
        'night_visit_count': 1,
        'last_visit_date': '2026-03-12',
        'coupon_balance': 50000,
        'memo': 'VIP',
        'created_at': '2026-03-12T10:00:00Z',
      });

      expect(customer.name, '강서N로드(2)(1)5678');
      expect(customer.memberType, '로드회원');
      expect(customer.effectiveSource, '로드');
      expect(customer.visitGrade, 'N');
      expect(customer.contactLabel, '강서N로드(2)(1)5678');
      expect(
        Customer.buildContactLabel(
          phone: '010-1111-2222',
          source: '마통',
          visitCount: 0,
          dayVisitCount: 0,
          nightVisitCount: 0,
        ),
        '강서New마통(0)(0)2222',
      );
    });

    test('visit grade uses day and night counts when visit count is stale', () {
      final customer = Customer.fromJson({
        'id': 'c2',
        'name': '강서S기존(3)(2)9999',
        'phone': '010-0000-9999',
        'member_type': '어플회원',
        'customer_source': '기존',
        'visit_count': 0,
        'day_visit_count': 3,
        'night_visit_count': 2,
        'coupon_balance': 0,
        'created_at': '2026-03-12T10:00:00Z',
      });

      expect(customer.effectiveVisitCount, 5);
      expect(customer.visitGrade, 'S');
      expect(customer.contactLabel, '강서S기존(3)(2)9999');
    });
  });

  group('Contact import parser', () {
    test('parses full label with visit breakdown', () {
      final candidate = ContactSyncService.parseCandidate(
        displayName: '강서N마통(2)(1)5678',
        phone: '010-1234-5678',
      );

      expect(candidate, isNotNull);
      expect(candidate!.source, '마통');
      expect(candidate.visitCount, 3);
      expect(candidate.dayVisitCount, 2);
      expect(candidate.nightVisitCount, 1);
    });

    test('infers visits from grade when breakdown is missing', () {
      final candidate = ContactSyncService.parseCandidate(
        displayName: '강서G로드5678',
        phone: '010-1234-5678',
      );

      expect(candidate, isNotNull);
      expect(candidate!.source, '로드');
      expect(candidate.visitCount, 10);
      expect(candidate.dayVisitCount, 10);
      expect(candidate.nightVisitCount, 0);
    });

    test('parses coupon-style label with extra token', () {
      final candidate = ContactSyncService.parseCandidate(
        displayName: '강서N마통,스페셜(0)(1)1234',
        phone: '010-9999-1234',
      );

      expect(candidate, isNotNull);
      expect(candidate!.source, '마통');
      expect(candidate.visitCount, 2);
      expect(candidate.dayVisitCount, 0);
      expect(candidate.nightVisitCount, 1);
    });

    test('parses dashed grade label', () {
      final candidate = ContactSyncService.parseCandidate(
        displayName: '강서-N-마통(1)(0)1234',
        phone: '010-9999-1234',
      );

      expect(candidate, isNotNull);
      expect(candidate!.source, '마통');
      expect(candidate.visitCount, 2);
    });

    test('parses label when phone digits come before counts', () {
      final candidate = ContactSyncService.parseCandidate(
        displayName: '강서N마통1234(3)(2)',
        phone: '010-9999-1234',
      );

      expect(candidate, isNotNull);
      expect(candidate!.source, '마통');
      expect(candidate.visitCount, 5);
      expect(candidate.dayVisitCount, 3);
      expect(candidate.nightVisitCount, 2);
    });

    test('parses hello and naver contacts', () {
      final helloCandidate = ContactSyncService.parseCandidate(
        displayName: '강서N헬로(1)(1)4321',
        phone: '010-1111-4321',
      );
      final naverCandidate = ContactSyncService.parseCandidate(
        displayName: '강서S네이버(4)(2)8765',
        phone: '010-2222-8765',
      );

      expect(helloCandidate, isNotNull);
      expect(helloCandidate!.source, '헬로');
      expect(naverCandidate, isNotNull);
      expect(naverCandidate!.source, '네이버');
    });
  });
}
