import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/service_menu.dart';
import '../models/customer.dart';
import '../models/reservation.dart';
import '../services/contact_sync_service.dart';
import '../services/sms_service.dart';
import '../services/supabase_service.dart';

class ReservationAddScreen extends StatefulWidget {
  const ReservationAddScreen({
    super.key,
    this.initialCustomer,
    this.initialPhone,
    this.initialDate,
    this.initialTime,
    this.initialSource,
    this.initialReservation,
  });

  final Customer? initialCustomer;
  final String? initialPhone;
  final DateTime? initialDate;
  final TimeOfDay? initialTime;
  final String? initialSource;
  /// 수정 모드: null이면 신규 등록, non-null이면 해당 예약 수정
  final Reservation? initialReservation;

  @override
  State<ReservationAddScreen> createState() => _ReservationAddScreenState();
}

class _ReservationAddScreenState extends State<ReservationAddScreen> {
  static const _sources = [
    '\uB9C8\uD1B5',
    '\uD558\uC774\uD0C0\uC774',
    '\uB9C8\uB9F5',
    '\uB85C\uB4DC',
    '\uAE30\uC874',
    '\uBC34\uB4DC',
  ];

  static final _serviceNames =
      kServiceMenu.values.first.map((service) => service.name).toList();

  final _service = SupabaseService();
  final _formKey = GlobalKey<FormState>();
  final _searchCtrl = TextEditingController();
  final _manualPhoneCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();

  Customer? _selectedCustomer;
  bool _isManualMode = false;
  List<Customer> _searchResults = [];
  Timer? _searchDebounce;

  late DateTime _date;
  TimeOfDay? _time;
  String? _serviceName;
  String _source = '\uAE30\uC874';
  bool _isSaving = false;

  bool get _isEditMode => widget.initialReservation != null;

  @override
  void initState() {
    super.initState();

    if (widget.initialReservation != null) {
      final r = widget.initialReservation!;
      _date = r.reservedDate;
      final parts = r.reservedTime.split(':');
      _time = TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 0,
        minute: int.tryParse(parts[1]) ?? 0,
      );
      _serviceName = r.serviceName;
      _source = r.source;
      _memoCtrl.text = r.memo ?? '';
      return;
    }

    _date = widget.initialDate ?? _today();
    _time = widget.initialTime;
    _source = widget.initialSource ?? _source;

    if (widget.initialCustomer != null) {
      _selectedCustomer = widget.initialCustomer;
      _source = _reservationSourceFromCustomer(widget.initialCustomer!);
    } else if (widget.initialPhone != null) {
      _isManualMode = true;
      _manualPhoneCtrl.text = widget.initialPhone!;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _manualPhoneCtrl.dispose();
    _memoCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  int? _servicePriceForCurrentSelection() {
    if (_serviceName == null) return null;
    final menus = kServiceMenu.values.toList();
    if (menus.isEmpty) return null;

    final useRoadMenu = (_selectedCustomer?.effectiveSource == '\uB85C\uB4DC') ||
        (_selectedCustomer == null && _manualCustomerSource == '\uB85C\uB4DC');
    final menuIndex = useRoadMenu ? 0 : (menus.length > 1 ? 1 : 0);

    for (final service in menus[menuIndex]) {
      if (service.name == _serviceName) return service.price;
    }
    return null;
  }

  String get _manualCustomerSource => switch (_source) {
        '\uB9C8\uD1B5' => '\uB9C8\uD1B5',
        '\uD558\uC774\uD0C0\uC774' => '\uD558\uC774',
        '\uB9C8\uB9F5' => '\uB9C8\uB9F5',
        '\uB85C\uB4DC' => '\uB85C\uB4DC',
        '\uBC34\uB4DC' => '\uBC34\uB4DC',
        _ => '\uAE30\uC874',
      };

  String _reservationSourceFromCustomer(Customer customer) {
    return switch (customer.effectiveSource) {
      '\uD558\uC774' => '\uD558\uC774\uD0C0\uC774',
      '\uB9C8\uD1B5' => '\uB9C8\uD1B5',
      '\uB9C8\uB9F5' => '\uB9C8\uB9F5',
      '\uB85C\uB4DC' => '\uB85C\uB4DC',
      '\uBC34\uB4DC' => '\uBC34\uB4DC',
      _ => '\uAE30\uC874',
    };
  }

  String get _manualMemberType => _manualCustomerSource == '\uB85C\uB4DC'
      ? '\uB85C\uB4DC\uD68C\uC6D0'
      : '\uC5B4\uD50C\uD68C\uC6D0';

  String _manualPreviewLabel() {
    return Customer.buildContactLabel(
      phone: _manualPhoneCtrl.text,
      source: _manualCustomerSource,
      visitCount: 0,
      dayVisitCount: 0,
      nightVisitCount: 0,
    );
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      final results = await _service.searchCustomers(query.trim());
      if (!mounted) return;
      setState(() => _searchResults = results);
    });
  }

  void _selectCustomer(Customer customer) {
    setState(() {
      _selectedCustomer = customer;
      _searchResults = [];
      _searchCtrl.clear();
      _source = _reservationSourceFromCustomer(customer);
    });
  }

  void _clearCustomer() {
    setState(() {
      _selectedCustomer = null;
      _isManualMode = false;
      _searchResults = [];
      _searchCtrl.clear();
    });
  }

  void _switchToManual() {
    setState(() {
      _isManualMode = true;
      _searchResults = [];
      _searchCtrl.clear();
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() => _time = picked);
    }
  }

  Future<void> _save() async {
    if (_time == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('예약 시간을 선택해주세요')),
      );
      return;
    }

    final hour = _time!.hour.toString().padLeft(2, '0');
    final minute = _time!.minute.toString().padLeft(2, '0');
    final timeStr = '$hour:$minute';
    final memo = _memoCtrl.text.trim().isEmpty ? null : _memoCtrl.text.trim();

    setState(() => _isSaving = true);
    try {
      // ── 수정 모드 ──────────────────────────────────────────
      if (_isEditMode) {
        await _service.updateReservation(
          reservationId: widget.initialReservation!.id,
          reservedDate: _date,
          reservedTime: timeStr,
          serviceName: _serviceName,
          source: _source,
          memo: memo,
        );
        if (mounted) Navigator.pop(context, true);
        return;
      }

      // ── 신규 등록 모드 ─────────────────────────────────────
      if (!_formKey.currentState!.validate()) return;

      late final String name;
      late final String phone;
      String? customerId;

      if (_selectedCustomer != null) {
        final updated = await _service.updateCustomerProfile(
          customerId: _selectedCustomer!.id,
          name: _selectedCustomer!.contactLabel,
          memberType: _manualMemberType,
          customerSource: _manualCustomerSource,
        );
        _selectedCustomer = updated;
        name = updated.contactLabel;
        phone = updated.phone;
        customerId = updated.id;
      } else {
        phone = _manualPhoneCtrl.text.trim();
        final created = await _service.addCustomer(
          name: _manualPreviewLabel(),
          phone: phone,
          memberType: _manualMemberType,
          customerSource: _manualCustomerSource,
          memo: null,
        );
        _selectedCustomer = created;
        name = created.contactLabel;
        customerId = created.id;
      }

      final result = await _service.addReservation(
        customerId: customerId,
        customerName: name,
        customerPhone: phone,
        reservedDate: _date,
        reservedTime: timeStr,
        serviceName: _serviceName,
        source: _source,
        memo: memo,
      );

      if (result.customer != null) {
        await ContactSyncService.syncCustomer(result.customer!);
      }

      if (result.couponDeduct > 0 && phone.isNotEmpty && _serviceName != null) {
        final remaining = result.customer?.couponBalance ?? 0;
        final requestedPrice =
            _servicePriceForCurrentSelection() ?? result.couponDeduct;
        final sent = await SmsService.sendCouponDeductionMessage(
          phone: phone,
          serviceName: _serviceName!,
          remaining: remaining,
          usedAllCoupons: result.additionalPaymentRequired ||
              requestedPrice > result.couponDeduct,
        );
        if (!sent && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('SMS 발송에 실패했습니다.')),
          );
        }
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장에 실패했습니다: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dateFmt = DateFormat('yyyy\uB144 M\uC6D4 d\uC77C (E)', 'ko_KR');

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? '예약 수정' : '예약 등록'),
        backgroundColor: colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
            children: [
              const _SectionLabel('\uACE0\uAC1D'),
              const SizedBox(height: 8),
              _buildCustomerSection(),
              const SizedBox(height: 20),
              const _SectionLabel('\uB0A0\uC9DC *'),
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.calendar_today),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                  ),
                  child: Text(dateFmt.format(_date)),
                ),
              ),
              const SizedBox(height: 16),
              const _SectionLabel('\uC2DC\uAC04 *'),
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickTime,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.access_time),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    hintText: _time == null
                        ? '\uC2DC\uAC04 \uC120\uD0DD'
                        : null,
                  ),
                  child: Text(
                    _time != null
                        ? '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}'
                        : '\uC2DC\uAC04 \uC120\uD0DD',
                    style: _time == null
                        ? TextStyle(color: Colors.grey[500])
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const _SectionLabel('\uC11C\uBE44\uC2A4'),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: _serviceName,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.spa),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                ),
                hint: const Text('\uC120\uD0DD \uC548 \uD568'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('\uC120\uD0DD \uC548 \uD568'),
                  ),
                  ..._serviceNames.map(
                    (service) => DropdownMenuItem<String?>(
                      value: service,
                      child: Text(service),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _serviceName = value),
              ),
              const SizedBox(height: 16),
              const _SectionLabel('\uC608\uC57D \uACBD\uB85C'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _sources.map((source) {
                  final selected = _source == source;
                  return ChoiceChip(
                    label: Text(source),
                    selected: selected,
                    onSelected: (_) => setState(() => _source = source),
                    selectedColor: colorScheme.primary,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : null,
                      fontWeight: selected ? FontWeight.bold : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const _SectionLabel('\uBA54\uBAA8'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _memoCtrl,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.note),
                  hintText: '\uBA54\uBAA8 (\uC120\uD0DD)',
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: ElevatedButton(
            onPressed: _isSaving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isSaving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    _isEditMode ? '수정 저장' : '예약 저장',
                    style: const TextStyle(fontSize: 16),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomerSection() {
    // 수정 모드: 고객 정보 읽기 전용
    if (_isEditMode) {
      final r = widget.initialReservation!;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.grey[300],
              child: Text(
                r.customerName.isNotEmpty ? r.customerName[0] : '?',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.customerName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    r.customerPhone,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Icon(Icons.lock_outline, size: 16, color: Colors.grey[400]),
          ],
        ),
      );
    }

    if (_selectedCustomer != null) {
      return _SelectedCustomerTile(
        customer: _selectedCustomer!,
        onClear: _clearCustomer,
      );
    }

    if (_isManualMode) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _manualPhoneCtrl,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: '\uC804\uD654\uBC88\uD638 *',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.phone),
              hintText: '010-0000-0000',
            ),
            keyboardType: TextInputType.phone,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return '\uC804\uD654\uBC88\uD638\uB97C \uC785\uB825\uD574\uC8FC\uC138\uC694';
              }
              return null;
            },
          ),
          const SizedBox(height: 10),
          InputDecorator(
            decoration: InputDecoration(
              labelText: '\uACE0\uAC1D\uBA85 \uBBF8\uB9AC\uBCF4\uAE30',
              border: const OutlineInputBorder(),
              helperText:
                  '\uC608\uC57D \uACBD\uB85C \uAE30\uC900 \uC720\uC785\uACBD\uB85C: $_manualCustomerSource',
              prefixIcon: const Icon(Icons.contacts_outlined),
            ),
            child: Text(
              _manualPreviewLabel(),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _clearCustomer,
            icon: const Icon(Icons.search, size: 16),
            label: const Text(
              '\uACE0\uAC1D \uAC80\uC0C9\uC73C\uB85C \uB3CC\uC544\uAC00\uAE30',
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchCtrl,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            hintText: '\uC774\uB984 \uB610\uB294 \uC804\uD654\uBC88\uD638 \uAC80\uC0C9',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _searchResults = []);
                    },
                  )
                : null,
          ),
        ),
        if (_searchResults.isNotEmpty) ...[
          const SizedBox(height: 4),
          Card(
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                ..._searchResults.take(5).map(
                      (customer) => ListTile(
                        dense: true,
                        title: Text(customer.contactLabel),
                        subtitle: Text(customer.phone),
                        trailing: Text(
                          customer.memberType,
                          style: const TextStyle(fontSize: 12),
                        ),
                        onTap: () => _selectCustomer(customer),
                      ),
                    ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _switchToManual,
          icon: const Icon(Icons.edit, size: 16),
          label: const Text('\uBBF8\uB4F1\uB85D \uACE0\uAC1D \uC9C1\uC811 \uC785\uB825'),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.grey[700],
      ),
    );
  }
}

class _SelectedCustomerTile extends StatelessWidget {
  const _SelectedCustomerTile({
    required this.customer,
    required this.onClear,
  });

  final Customer customer;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: Text(
              customer.contactLabel.isNotEmpty ? customer.contactLabel[0] : '?',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer.contactLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                Text(
                  customer.phone,
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onClear,
            tooltip: '\uC120\uD0DD \uD574\uC81C',
          ),
        ],
      ),
    );
  }
}
