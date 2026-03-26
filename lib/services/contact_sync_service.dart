import 'dart:developer' as dev;

import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../app_config.dart';
import '../models/customer.dart';
import 'auth_service.dart';
import 'phone_service.dart';
import 'supabase_service.dart';

enum ContactImportMode {
  overwriteAll,
  addOnlyNew,
}

class ContactImportSummary {
  final int created;
  final int updated;
  final int skipped;

  const ContactImportSummary({
    required this.created,
    required this.updated,
    required this.skipped,
  });
}

class ContactExportSummary {
  final int created;
  final int updated;
  final int skipped;

  const ContactExportSummary({
    required this.created,
    required this.updated,
    required this.skipped,
  });
}

class ContactImportPreview {
  final int totalScanned;
  final int toCreate;
  final int toUpdate;
  final int toSkip;

  const ContactImportPreview({
    required this.totalScanned,
    required this.toCreate,
    required this.toUpdate,
    required this.toSkip,
  });
}

class ImportedCustomerCandidate {
  final String phone;
  final String source;
  final int visitCount;
  final int dayVisitCount;
  final int nightVisitCount;
  final String? memo;

  const ImportedCustomerCandidate({
    required this.phone,
    required this.source,
    required this.visitCount,
    required this.dayVisitCount,
    required this.nightVisitCount,
    this.memo,
  });
}

class PreparedContactImportEntry {
  final String contactId;
  final ImportedCustomerCandidate? candidate;
  final bool existsByPhone;
  final bool existsByName;

  const PreparedContactImportEntry({
    required this.contactId,
    required this.candidate,
    required this.existsByPhone,
    required this.existsByName,
  });
}

class PreparedContactImport {
  final ContactImportMode mode;
  final ContactImportPreview preview;
  final List<PreparedContactImportEntry> entries;
  final Map<String, Customer> customerIndex;

  const PreparedContactImport({
    required this.mode,
    required this.preview,
    required this.entries,
    required this.customerIndex,
  });
}

typedef ContactImportProgressCallback =
    void Function(int current, int total, String phase);

class ContactSyncService {
  ContactSyncService._();

  static const _sourceAliases = <String, String>{
    '\ub9c8\ud1b5': '\ub9c8\ud1b5',
    '\ub9c8\ud1b5,\uc2a4\ud398\uc15c': '\ub9c8\ud1b5',
    '\ub9c8\ub9f5': '\ub9c8\ub9f5',
    '\ub9c8\ub9e5': '\ub9c8\ub9e5',
    '\ub9c8\ubbfc': '\ub9c8\ubbfc',
    '\ud558\uc774': '\ud558\uc774',
    '\ud558\uc774\ud0c0\uc774': '\ud558\uc774',
    '\ub85c\ub4dc': '\ub85c\ub4dc',
    '\uae30\uc874': '\uae30\uc874',
    '\ubc34\ub4dc': '\ubc34\ub4dc',
    '\ud5ec\ub85c': '\ud5ec\ub85c',
    '\ub124\uc774\ubc84': '\ub124\uc774\ubc84',
  };

  static final _countPattern = RegExp(r'\((\d+)\)');
  static final _gradePattern = RegExp(r'(?:-)?(New|VV|N|S|G|V)(?:-)?');

  static Future<bool> _ensurePermission() async {
    final status =
        await FlutterContacts.permissions.request(PermissionType.readWrite);
    return status == PermissionStatus.granted ||
        status == PermissionStatus.limited;
  }

  static String _normalize(String value) {
    return PhoneService.normalize(value) ?? value.replaceAll(RegExp(r'\D'), '');
  }

  static int _minimumVisitCountForGrade(String grade) {
    return switch (grade) {
      'New' => 1,
      'N' => 2,
      'S' => 5,
      'G' => 10,
      'V' => 20,
      'VV' => 50,
      _ => 1,
    };
  }

  static String? _matchSource(String body) {
    for (final alias in _sourceAliases.keys) {
      if (body.contains(alias)) {
        return _sourceAliases[alias];
      }
    }
    return null;
  }

  static ImportedCustomerCandidate? parseCandidate({
    required String displayName,
    required String phone,
  }) {
    final normalized = displayName.replaceAll(' ', '').trim();
    if (!normalized.startsWith(AuthService.contactPrefix)) {
      return null;
    }

    final body = normalized.substring(AuthService.contactPrefix.length);
    final gradeMatch = _gradePattern.firstMatch(body);
    if (gradeMatch == null) {
      return null;
    }

    final source = _matchSource(body);
    if (source == null) {
      return null;
    }

    // 메모 추출: 경로명 뒤 콤마~첫 번째 (숫자) 사이의 텍스트
    // 예: "로드,쿠폰X(0)(1)1234" → memo = "쿠폰X"
    String? memo;
    final sourceAlias = _sourceAliases.keys.firstWhere((a) => body.contains(a));
    final afterSource = body.substring(body.indexOf(sourceAlias) + sourceAlias.length);
    if (afterSource.startsWith(',')) {
      final firstParen = afterSource.indexOf('(');
      if (firstParen > 1) {
        memo = afterSource.substring(1, firstParen).trim();
        if (memo.isEmpty) memo = null;
      }
    }

    final counts = _countPattern
        .allMatches(body)
        .map((match) => int.tryParse(match.group(1) ?? ''))
        .whereType<int>()
        .toList();
    final minimumVisitCount = _minimumVisitCountForGrade(gradeMatch.group(1)!);
    final hasVisitBreakdown = counts.length >= 2;
    final dayVisitCount = hasVisitBreakdown ? counts[0] : minimumVisitCount;
    final nightVisitCount = hasVisitBreakdown ? counts[1] : 0;
    final visitCount = hasVisitBreakdown
        ? [minimumVisitCount, dayVisitCount + nightVisitCount]
            .reduce((a, b) => a > b ? a : b)
        : minimumVisitCount;

    return ImportedCustomerCandidate(
      phone: phone,
      source: source,
      visitCount: visitCount,
      dayVisitCount: dayVisitCount,
      nightVisitCount: nightVisitCount,
      memo: memo,
    );
  }

  static const _nativeChannel = MethodChannel('com.example.the_thai/native_call');

  static Future<List<Map<String, String>>> _fetchNativeContacts(
    String prefix,
  ) async {
    final raw = await _nativeChannel.invokeListMethod<Map>(
      'getContactsByPrefix',
      {'prefix': prefix},
    );
    return (raw ?? [])
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v.toString())))
        .toList();
  }

  static Future<String?> _findContactIdByPhone(String phone) async {
    final raw = await _nativeChannel.invokeMapMethod<String, String>(
      'findContactByPhone',
      {'phone': _normalize(phone)},
    );
    return raw?['id'];
  }

  static Future<void> _syncContactById(
    String contactId,
    Customer customer,
  ) async {
    await _nativeChannel.invokeMethod<void>('updateContactName', {
      'rawId': contactId,
      'name': customer.contactLabel,
    });
  }

  static Future<void> syncCustomer(Customer customer) async {
    final granted = await _ensurePermission();
    if (!granted) return;

    final contactId = await _findContactIdByPhone(customer.phone);
    if (contactId != null) {
      await _syncContactById(contactId, customer);
      return;
    }

    await FlutterContacts.create(Contact(
      name: Name(first: customer.contactLabel, last: ''),
      phones: [Phone(number: customer.phone)],
    ));
  }

  static bool _shouldImportEntry(
    PreparedContactImportEntry entry,
    ContactImportMode mode,
  ) {
    if (entry.candidate == null) {
      return false;
    }

    return switch (mode) {
      ContactImportMode.overwriteAll => true,
      ContactImportMode.addOnlyNew => !entry.existsByPhone && !entry.existsByName,
    };
  }

  static Future<PreparedContactImport> prepareContactsImport(
    SupabaseService service, {
    ContactImportMode mode = ContactImportMode.overwriteAll,
    ContactImportProgressCallback? onProgress,
  }) async {
    final granted = await _ensurePermission();
    if (!granted) {
      return PreparedContactImport(
        mode: mode,
        preview: const ContactImportPreview(totalScanned: 0, toCreate: 0, toUpdate: 0, toSkip: 0),
        entries: const [],
        customerIndex: const {},
      );
    }

    final contacts = await _fetchNativeContacts(AuthService.contactPrefix);
    dev.log('[ContactSync] 네이티브 스캔 반환: ${contacts.length}개', name: 'ContactSync');

    final customerIndex = await service.getCustomerPhoneIndex();
    final customerNames = (await service.getCustomers())
        .map((customer) => customer.name.trim())
        .where((name) => name.isNotEmpty)
        .toSet();

    var toCreate = 0;
    var toUpdate = 0;
    var toSkip = 0;
    final entries = <PreparedContactImportEntry>[];

    for (var i = 0; i < contacts.length; i++) {
      final raw = contacts[i];
      onProgress?.call(i + 1, contacts.length, 'preview');

      try {
        final contactId = raw['id'] ?? '';
        final displayName = (raw['name'] ?? '').trim();
        final phone = raw['phone'] ?? '';

        if (displayName.isEmpty || phone.isEmpty) {
          toSkip++;
          entries.add(PreparedContactImportEntry(
            contactId: contactId,
            candidate: null,
            existsByPhone: false,
            existsByName: false,
          ));
          continue;
        }

        final candidate = parseCandidate(
          displayName: displayName,
          phone: phone,
        );
        if (candidate == null) {
          toSkip++;
          entries.add(PreparedContactImportEntry(
            contactId: contactId,
            candidate: null,
            existsByPhone: false,
            existsByName: false,
          ));
          continue;
        }

        final normalizedPhone = _normalize(candidate.phone);
        final existsByPhone = customerIndex.containsKey(normalizedPhone);
        final existsByName = customerNames.contains(displayName);
        final entry = PreparedContactImportEntry(
          contactId: contactId,
          candidate: candidate,
          existsByPhone: existsByPhone,
          existsByName: existsByName,
        );

        if (_shouldImportEntry(entry, mode)) {
          if (existsByPhone) {
            toUpdate++;
          } else {
            toCreate++;
          }
        } else {
          toSkip++;
        }

        entries.add(entry);
      } catch (_) {
        toSkip++;
        entries.add(PreparedContactImportEntry(
          contactId: raw['id'] ?? '',
          candidate: null,
          existsByPhone: false,
          existsByName: false,
        ));
      }
    }

    dev.log(
      '[ContactSync] 필터 결과: create=$toCreate, update=$toUpdate, skip=$toSkip',
      name: 'ContactSync',
    );

    return PreparedContactImport(
      mode: mode,
      preview: ContactImportPreview(
        totalScanned: contacts.length,
        toCreate: toCreate,
        toUpdate: toUpdate,
        toSkip: toSkip,
      ),
      entries: entries,
      customerIndex: customerIndex,
    );
  }

  static Future<ContactImportSummary> importPreparedContactsToDatabase(
    SupabaseService service,
    PreparedContactImport prepared, {
    ContactImportProgressCallback? onProgress,
  }) async {
    final granted = await _ensurePermission();
    if (!granted) {
      return const ContactImportSummary(created: 0, updated: 0, skipped: 0);
    }

    final customerIndex = Map<String, Customer>.from(prepared.customerIndex);
    final toCreate = <PreparedContactImportEntry>[];
    final toUpdate = <PreparedContactImportEntry>[];
    final seenPhones = <String>{};

    for (final entry in prepared.entries) {
      if (!_shouldImportEntry(entry, prepared.mode)) {
        continue;
      }

      final normalizedPhone = _normalize(entry.candidate!.phone);
      if (!seenPhones.add(normalizedPhone)) {
        continue;
      }

      if (entry.existsByPhone) {
        toUpdate.add(entry);
      } else {
        toCreate.add(entry);
      }
    }

    final resultByPhone = <String, Customer>{};

    if (toCreate.isNotEmpty) {
      onProgress?.call(0, toCreate.length, 'create');
      try {
        final rows = toCreate.map((entry) {
          final candidate = entry.candidate!;
          final memberType = candidate.source == '\ub85c\ub4dc'
              ? '\ub85c\ub4dc\ud68c\uc6d0'
              : '\uc5b4\ud50c\ud68c\uc6d0';
          return {
            'name': Customer.buildContactLabel(
              phone: candidate.phone,
              source: candidate.source,
              visitCount: candidate.visitCount,
              dayVisitCount: candidate.dayVisitCount,
              nightVisitCount: candidate.nightVisitCount,
            ),
            'phone': _normalize(candidate.phone),
            'member_type': memberType,
            'customer_source': candidate.source,
            'visit_count': candidate.visitCount,
            'day_visit_count': candidate.dayVisitCount,
            'night_visit_count': candidate.nightVisitCount,
            if (candidate.memo != null) 'memo': candidate.memo,
          };
        }).toList();

        dev.log('[ContactSync] batch insert 시도: ${rows.length}개', name: 'ContactSync');
        final created = await service.batchAddCustomers(rows);
        dev.log('[ContactSync] batch insert 응답: ${created.length}개', name: 'ContactSync');
        for (final customer in created) {
          final normalizedPhone = _normalize(customer.phone);
          resultByPhone[normalizedPhone] = customer;
          customerIndex[normalizedPhone] = customer;
        }
      } catch (e) {
        dev.log('[ContactSync] batch insert 실패, 개별 처리로 전환: $e', name: 'ContactSync');
        var completed = 0;
        for (final entry in toCreate) {
          try {
            final candidate = entry.candidate!;
            final memberType = candidate.source == '\ub85c\ub4dc'
                ? '\ub85c\ub4dc\ud68c\uc6d0'
                : '\uc5b4\ud50c\ud68c\uc6d0';
            final customer = await service.addCustomer(
              name: Customer.buildContactLabel(
                phone: candidate.phone,
                source: candidate.source,
                visitCount: candidate.visitCount,
                dayVisitCount: candidate.dayVisitCount,
                nightVisitCount: candidate.nightVisitCount,
              ),
              phone: _normalize(candidate.phone),
              memberType: memberType,
              customerSource: candidate.source,
              visitCount: candidate.visitCount,
              dayVisitCount: candidate.dayVisitCount,
              nightVisitCount: candidate.nightVisitCount,
              memo: candidate.memo,
            );
            final normalizedPhone = _normalize(customer.phone);
            resultByPhone[normalizedPhone] = customer;
            customerIndex[normalizedPhone] = customer;
          } catch (e) {
            dev.log('[ContactSync] 개별 insert 실패 (${entry.candidate?.phone}): $e', name: 'ContactSync');
          }
          onProgress?.call(++completed, toCreate.length, 'create');
        }
      }
      onProgress?.call(toCreate.length, toCreate.length, 'create');
    }

    if (toUpdate.isNotEmpty) {
      onProgress?.call(0, toUpdate.length, 'update');
      var completed = 0;
      final results = await Future.wait(
        toUpdate.map((entry) async {
          try {
            final candidate = entry.candidate!;
            final existing = customerIndex[_normalize(candidate.phone)];
            if (existing == null) {
              return null;
            }

            final customer = await service.updateImportedCustomerFromExisting(
              existing: existing,
              customerSource: candidate.source,
              visitCount: candidate.visitCount,
              dayVisitCount: candidate.dayVisitCount,
              nightVisitCount: candidate.nightVisitCount,
              memo: candidate.memo,
            );
            onProgress?.call(++completed, toUpdate.length, 'update');
            return customer;
          } catch (_) {
            onProgress?.call(++completed, toUpdate.length, 'update');
            return null;
          }
        }),
      );

      for (final customer in results) {
        if (customer == null) {
          continue;
        }
        resultByPhone[_normalize(customer.phone)] = customer;
      }
    }

    final syncEntries = [...toCreate, ...toUpdate]
        .where((entry) => resultByPhone.containsKey(_normalize(entry.candidate!.phone)))
        .toList();

    for (var i = 0; i < syncEntries.length; i++) {
      final entry = syncEntries[i];
      final customer = resultByPhone[_normalize(entry.candidate!.phone)]!;
      try {
        await _syncContactById(entry.contactId, customer);
      } catch (_) {
        // Keep DB import successful even when local contact sync fails.
      }
      onProgress?.call(i + 1, syncEntries.length, 'sync');
    }

    final created = toCreate
        .where((entry) => resultByPhone.containsKey(_normalize(entry.candidate!.phone)))
        .length;
    final updated = toUpdate
        .where((entry) => resultByPhone.containsKey(_normalize(entry.candidate!.phone)))
        .length;
    final skipped =
        prepared.entries.length - created - updated + (toCreate.length - created) + (toUpdate.length - updated);

    return ContactImportSummary(
      created: created,
      updated: updated,
      skipped: skipped,
    );
  }

  static Future<ContactImportSummary> importContactsToDatabase(
    SupabaseService service, {
    ContactImportMode mode = ContactImportMode.overwriteAll,
    ContactImportProgressCallback? onProgress,
  }) async {
    final prepared = await prepareContactsImport(
      service,
      mode: mode,
      onProgress: onProgress,
    );
    return importPreparedContactsToDatabase(
      service,
      prepared,
      onProgress: onProgress,
    );
  }

  static Future<ContactImportPreview> previewContactsToDatabase(
    SupabaseService service, {
    ContactImportMode mode = ContactImportMode.overwriteAll,
    ContactImportProgressCallback? onProgress,
  }) async {
    final prepared = await prepareContactsImport(
      service,
      mode: mode,
      onProgress: onProgress,
    );
    return prepared.preview;
  }

  /// DB → 로컬 주소록 내보내기
  /// DB의 모든 고객을 기준으로 로컬 주소록의 이름을 [contactLabel]로 덮어씁니다.
  /// 로컬에 없는 고객은 새로 생성합니다.
  static Future<ContactExportSummary> exportDatabaseToContacts(
    SupabaseService service, {
    ContactImportProgressCallback? onProgress,
  }) async {
    final granted = await _ensurePermission();
    if (!granted) {
      return const ContactExportSummary(created: 0, updated: 0, skipped: 0);
    }

    final customers = await service.getCustomers();

    final allContacts = await FlutterContacts.getAll(
      properties: {ContactProperty.name, ContactProperty.phone},
    );

    // phone(normalized) → Contact index
    final contactByPhone = <String, Contact>{};
    for (final contact in allContacts) {
      for (final p in contact.phones) {
        final number = (p.normalizedNumber?.isNotEmpty ?? false)
            ? p.normalizedNumber!
            : p.number;
        final key = _normalize(number);
        if (key.isNotEmpty) {
          contactByPhone[key] = contact;
        }
      }
    }

    var created = 0;
    var updated = 0;
    var skipped = 0;

    for (var i = 0; i < customers.length; i++) {
      final customer = customers[i];
      onProgress?.call(i + 1, customers.length, 'export');
      try {
        final key = _normalize(customer.phone);
        final existing = contactByPhone[key];

        if (existing != null) {
          final existingName = existing.displayName?.trim() ?? '';
          if (existingName == customer.contactLabel) {
            skipped++;
          } else {
            final updated_ = existing.copyWith(
              name: Name(first: customer.contactLabel, last: ''),
              phones: existing.phones.isEmpty
                  ? [Phone(number: customer.phone)]
                  : [
                      Phone(
                        number: customer.phone,
                        label: existing.phones.first.label,
                        normalizedNumber: existing.phones.first.normalizedNumber,
                        isPrimary: existing.phones.first.isPrimary,
                        metadata: existing.phones.first.metadata,
                      ),
                      ...existing.phones.skip(1),
                    ],
            );
            await FlutterContacts.update(updated_);
            updated++;
          }
        } else {
          final contact = Contact(
            name: Name(first: customer.contactLabel, last: ''),
            phones: [Phone(number: customer.phone)],
          );
          await FlutterContacts.create(contact);
          created++;
        }
      } catch (_) {
        skipped++;
      }
    }

    return ContactExportSummary(
      created: created,
      updated: updated,
      skipped: skipped,
    );
  }
}
