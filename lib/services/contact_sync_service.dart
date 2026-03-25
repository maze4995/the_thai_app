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
  final int toCreate;
  final int toUpdate;
  final int toSkip;

  const ContactImportPreview({
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

  const ImportedCustomerCandidate({
    required this.phone,
    required this.source,
    required this.visitCount,
    required this.dayVisitCount,
    required this.nightVisitCount,
  });
}

class PreparedContactImportEntry {
  final Contact contact;
  final ImportedCustomerCandidate? candidate;
  final bool existsByPhone;
  final bool existsByName;

  const PreparedContactImportEntry({
    required this.contact,
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
    );
  }

  static Future<Contact?> _findByPhone(String phone) async {
    final normalizedTarget = _normalize(phone);
    final contacts = await FlutterContacts.getAll(
      properties: {ContactProperty.name, ContactProperty.phone},
    );

    for (final contact in contacts) {
      for (final entry in contact.phones) {
        final number = (entry.normalizedNumber?.isNotEmpty ?? false)
            ? entry.normalizedNumber
            : entry.number;
        if (number != null && _normalize(number) == normalizedTarget) {
          return contact;
        }
      }
    }
    return null;
  }

  static Future<void> _syncImportedContact(
    Contact contact,
    Customer customer,
  ) async {
    final existingName = contact.displayName?.trim() ?? '';
    final primaryPhone = contact.phones.isNotEmpty
        ? contact.phones.first.number
        : customer.phone;
    final normalizedExisting = _normalize(primaryPhone);
    final normalizedCustomer = _normalize(customer.phone);

    if (existingName == customer.contactLabel &&
        normalizedExisting == normalizedCustomer) {
      return;
    }

    final updated = contact.copyWith(
      name: Name(first: customer.contactLabel, last: ''),
      phones: contact.phones.isEmpty
          ? [Phone(number: customer.phone)]
          : [
              Phone(
                number: customer.phone,
                label: contact.phones.first.label,
                normalizedNumber: contact.phones.first.normalizedNumber,
                isPrimary: contact.phones.first.isPrimary,
                metadata: contact.phones.first.metadata,
              ),
              ...contact.phones.skip(1),
            ],
    );
    await FlutterContacts.update(updated);
  }

  static Future<void> syncCustomer(Customer customer) async {
    final granted = await _ensurePermission();
    if (!granted) {
      return;
    }

    final existing = await _findByPhone(customer.phone);
    if (existing != null) {
      await _syncImportedContact(existing, customer);
      return;
    }

    final contact = Contact(
      name: Name(first: customer.contactLabel, last: ''),
      phones: [Phone(number: customer.phone)],
    );
    await FlutterContacts.create(contact);
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
        preview: const ContactImportPreview(toCreate: 0, toUpdate: 0, toSkip: 0),
        entries: const [],
        customerIndex: const {},
      );
    }

    final contacts = await FlutterContacts.getAll(
      properties: {ContactProperty.name, ContactProperty.phone},
    );
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
      final contact = contacts[i];
      onProgress?.call(i + 1, contacts.length, 'preview');

      try {
        final displayName = contact.displayName?.trim();
        if (displayName == null ||
            displayName.isEmpty ||
            !displayName.startsWith(AuthService.contactPrefix) ||
            contact.phones.isEmpty) {
          toSkip++;
          entries.add(
            PreparedContactImportEntry(
              contact: contact,
              candidate: null,
              existsByPhone: false,
              existsByName: false,
            ),
          );
          continue;
        }

        final candidate = parseCandidate(
          displayName: displayName,
          phone: contact.phones.first.number,
        );
        if (candidate == null) {
          toSkip++;
          entries.add(
            PreparedContactImportEntry(
              contact: contact,
              candidate: null,
              existsByPhone: false,
              existsByName: false,
            ),
          );
          continue;
        }

        final normalizedPhone = _normalize(candidate.phone);
        final existsByPhone = customerIndex.containsKey(normalizedPhone);
        final existsByName = customerNames.contains(displayName);
        final entry = PreparedContactImportEntry(
          contact: contact,
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
        entries.add(
          PreparedContactImportEntry(
            contact: contact,
            candidate: null,
            existsByPhone: false,
            existsByName: false,
          ),
        );
      }
    }

    return PreparedContactImport(
      mode: mode,
      preview: ContactImportPreview(
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
          };
        }).toList();

        final created = await service.batchAddCustomers(rows);
        for (final customer in created) {
          final normalizedPhone = _normalize(customer.phone);
          resultByPhone[normalizedPhone] = customer;
          customerIndex[normalizedPhone] = customer;
        }
      } catch (_) {
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
            );
            final normalizedPhone = _normalize(customer.phone);
            resultByPhone[normalizedPhone] = customer;
            customerIndex[normalizedPhone] = customer;
          } catch (_) {
            // Continue importing remaining contacts.
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
        await _syncImportedContact(entry.contact, customer);
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
