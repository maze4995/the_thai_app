import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/service_menu.dart';
import '../models/customer.dart';
import '../models/visit_history.dart';
import '../services/contact_sync_service.dart';
import '../services/sms_service.dart';
import '../services/supabase_service.dart';

class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({super.key, required this.customer});

  final Customer customer;

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  final _service = SupabaseService();
  final _memoController = TextEditingController();
  final _dateFormat = DateFormat('yyyy.MM.dd');
  final _wonFormat = NumberFormat('#,###', 'ko_KR');

  late Customer _customer;
  List<VisitHistory> _history = [];
  bool _isLoadingHistory = true;
  bool _isEditingMemo = false;

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
    _memoController.text = _customer.memo ?? '';
    _loadHistory();
  }

  @override
  void dispose() {
    _memoController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoadingHistory = true);
    try {
      final history = await _service.getVisitHistory(_customer.id);
      if (!mounted) return;
      setState(() => _history = history);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('\uBC29\uBB38 \uC774\uB825\uC744 \uBD88\uB7EC\uC624\uC9C0 \uBABB\uD588\uC2B5\uB2C8\uB2E4. $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  Future<void> _saveMemo() async {
    try {
      final memo = _memoController.text.trim();
      await _service.updateMemo(_customer.id, memo);
      final updated = _customer.copyWith(memo: memo.isNotEmpty ? memo : null);
      await _service.updateName(_customer.id, updated.contactLabel);
      await ContactSyncService.syncCustomer(updated);
      if (!mounted) return;
      setState(() {
        _customer = updated;
        _isEditingMemo = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('\uBA54\uBAA8\uB97C \uC800\uC7A5\uD588\uC2B5\uB2C8\uB2E4.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('\uBA54\uBAA8 \uC800\uC7A5\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4. $e'),
        ),
      );
    }
  }

  Future<void> _addVisit() async {
    final services = kServiceMenu[_customer.memberType] ?? [];

    final selected = await showDialog<ServiceItem>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('\uC11C\uBE44\uC2A4 \uC120\uD0DD (${_customer.memberType})'),
        contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: services.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, index) {
              final service = services[index];
              return ListTile(
                dense: true,
                title: Text(service.name),
                trailing: Text(
                  '${_wonFormat.format(service.price)}\uC6D0',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                onTap: () => Navigator.pop(dialogContext, service),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('\uCDE8\uC18C'),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;

    final balance = _customer.couponBalance;
    final int amountToDeduct;
    if (balance <= 0) {
      amountToDeduct = 0;
    } else if (balance >= selected.price) {
      amountToDeduct = selected.price;
    } else {
      amountToDeduct = balance;
    }

    final balanceAfter = balance - amountToDeduct;
    final isNormalVisit = amountToDeduct == 0;
    final isPartial = amountToDeduct > 0 && amountToDeduct < selected.price;
    final usedAllCoupons = amountToDeduct > 0 && balance > 0 && balance < selected.price;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('\uBC29\uBB38 \uAE30\uB85D'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ConfirmRow('\uACE0\uAC1D', _customer.contactLabel),
            _ConfirmRow('\uC11C\uBE44\uC2A4', selected.name),
            _ConfirmRow(
              '\uC11C\uBE44\uC2A4 \uAE08\uC561',
              '${_wonFormat.format(selected.price)}\uC6D0',
            ),
            const Divider(),
            if (isNormalVisit)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '\uCFE0\uD3F0\uC774 \uC5C6\uC5B4 \uC77C\uBC18 \uBC29\uBB38\uC73C\uB85C \uCC98\uB9AC\uB429\uB2C8\uB2E4.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              )
            else ...[
              _ConfirmRow(
                '\uD604\uC7AC \uCFE0\uD3F0',
                '${_wonFormat.format(balance)}\uC6D0',
              ),
              _ConfirmRow(
                '\uCC28\uAC10 \uAE08\uC561',
                '${_wonFormat.format(amountToDeduct)}\uC6D0',
                valueColor: Colors.red,
              ),
              _ConfirmRow(
                '\uCC28\uAC10 \uD6C4 \uCFE0\uD3F0',
                '${_wonFormat.format(balanceAfter)}\uC6D0',
                valueColor: Colors.green[700],
              ),
              if (isPartial)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    '\uCFE0\uD3F0\uC774 \uBD80\uC871\uD574 \uBCF4\uC720 \uCFE0\uD3F0\uB9CC \uCC28\uAC10\uB429\uB2C8\uB2E4.',
                    style: TextStyle(color: Colors.orange, fontSize: 12),
                  ),
                ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('\uCDE8\uC18C'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('\uD655\uC778'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final updatedCustomer = await _service.addVisit(
        customerId: _customer.id,
        serviceName: selected.name,
        servicePrice: selected.price,
        amountToDeduct: amountToDeduct,
      );
      await ContactSyncService.syncCustomer(updatedCustomer);
      if (!mounted) return;

      setState(() => _customer = updatedCustomer);
      await _loadHistory();
      if (!mounted) return;

      if (amountToDeduct > 0) {
        final sent = await SmsService.sendCouponDeductionMessage(
          phone: _customer.phone,
          serviceName: selected.name,
          remaining: updatedCustomer.couponBalance,
          usedAllCoupons: usedAllCoupons,
        );
        if (!sent && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('SMS 발송에 실패했습니다.')),
          );
        }
      }

      if (!mounted) return;

      if (isPartial) {
        final shortage = selected.price - amountToDeduct;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('\uCFE0\uD3F0 \uC794\uC561 \uBD80\uC871'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '\uC11C\uBE44\uC2A4 \uAE08\uC561: ${_wonFormat.format(selected.price)}\uC6D0',
                ),
                Text(
                  '\uCC28\uAC10\uB41C \uCFE0\uD3F0: ${_wonFormat.format(amountToDeduct)}\uC6D0',
                ),
                const SizedBox(height: 8),
                Text(
                  '\uCC28\uC561 ${_wonFormat.format(shortage)}\uC6D0\uC744 \uACB0\uC81C\uBC1B\uC73C\uC138\uC694.',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('\uD655\uC778'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('\uBC29\uBB38\uC744 \uAE30\uB85D\uD588\uC2B5\uB2C8\uB2E4. (${selected.name})'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('\uBC29\uBB38 \uAE30\uB85D\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4. $e'),
        ),
      );
    }
  }

  Future<void> _chargeCoupon() async {
    final amountController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('\uCFE0\uD3F0 \uCDA9\uC804'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '\uD604\uC7AC \uCFE0\uD3F0: ${_wonFormat.format(_customer.couponBalance)}\uC6D0',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '\uCDA9\uC804 \uAE08\uC561',
                suffixText: '\uC6D0',
                border: OutlineInputBorder(),
                hintText: '\uC608: 100000',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('\uCDE8\uC18C'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('\uCDA9\uC804'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final amount = int.tryParse(amountController.text.trim()) ?? 0;
    if (amount <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('\uC62C\uBC14\uB978 \uAE08\uC561\uC744 \uC785\uB825\uD574\uC8FC\uC138\uC694.'),
        ),
      );
      return;
    }

    try {
      final updated = await _service.chargeCoupon(_customer.id, amount);
      await ContactSyncService.syncCustomer(updated);
      if (!mounted) return;
      setState(() => _customer = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_wonFormat.format(amount)}\uC6D0\uC744 \uCDA9\uC804\uD588\uC2B5\uB2C8\uB2E4.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('\uCDA9\uC804\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4. $e'),
        ),
      );
    }
  }

  Future<void> _deleteVisitHistory(VisitHistory history) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('\uBC29\uBB38 \uC774\uB825 \uC0AD\uC81C'),
        content: Text(
          '${_dateFormat.format(history.visitDate)} ${history.serviceName} \uB0B4\uC5ED\uC744 \uC0AD\uC81C\uD558\uC2DC\uACA0\uC2B5\uB2C8\uAE4C?\n\uBC29\uBB38 \uC218 1\uD68C\uAC00 \uCC28\uAC10\uB429\uB2C8\uB2E4.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('\uCDE8\uC18C'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('\uC0AD\uC81C'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final updated = await _service.deleteVisitHistory(
        historyId: history.id,
        customerId: _customer.id,
        visitType: history.visitType,
      );
      await ContactSyncService.syncCustomer(updated);
      if (!mounted) return;
      setState(() => _customer = updated);
      await _loadHistory();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('\uC0AD\uC81C\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4. $e')),
      );
    }
  }

  Future<void> _editVisitHistory(VisitHistory history) async {
    var editDate = history.visitDate;
    var editType = history.visitType;
    final nameCtrl = TextEditingController(text: history.serviceName);
    final priceCtrl =
        TextEditingController(text: history.servicePrice > 0 ? history.servicePrice.toString() : '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('\uBC29\uBB38 \uC774\uB825 \uC218\uC815'),
          contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 날짜
                Row(
                  children: [
                    Text(
                      _dateFormat.format(editDate),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: editDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) setS(() => editDate = picked);
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('\uB0A0\uC9DC \uBCC0\uACBD'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 방문 유형
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: '\uC8FC\uAC04', label: Text('\uC8FC\uAC04')),
                    ButtonSegment(value: '\uC57C\uAC04', label: Text('\uC57C\uAC04')),
                  ],
                  selected: {editType},
                  onSelectionChanged: (s) => setS(() => editType = s.first),
                ),
                const SizedBox(height: 12),
                // 서비스명
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '\uC11C\uBE44\uC2A4\uBA85',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                // 서비스 금액
                TextField(
                  controller: priceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '\uC11C\uBE44\uC2A4 \uAE08\uC561',
                    suffixText: '\uC6D0',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('\uCDE8\uC18C'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('\uC800\uC7A5'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final updated = await _service.updateVisitHistory(
        historyId: history.id,
        customerId: _customer.id,
        visitDate: editDate,
        visitType: editType,
        serviceName: nameCtrl.text.trim(),
        servicePrice: int.tryParse(priceCtrl.text.trim()) ?? 0,
        prevVisitType: history.visitType,
      );
      await ContactSyncService.syncCustomer(updated);
      if (!mounted) return;
      setState(() => _customer = updated);
      await _loadHistory();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('\uC218\uC815\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4. $e')),
      );
    }
  }

  Future<void> _editCustomerInfo() async {
    final sourceOptions = ['마통', '하이타이', '마맵', '로드', '밴드', '기존'];
    final memberTypeOptions = ['로드회원', '어플회원'];

    var editSource = _customer.effectiveSource;
    var editMemberType = _customer.memberType;
    final nameCtrl = TextEditingController(text: _customer.name);
    final dayCtrl = TextEditingController(text: _customer.dayVisitCount.toString());
    final nightCtrl = TextEditingController(text: _customer.nightVisitCount.toString());
    final phoneCtrl = TextEditingController(text: _customer.phone);
    final memoCtrl = TextEditingController(text: _customer.memo ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('고객 정보 수정'),
          contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 이름
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '이름',
                    border: OutlineInputBorder(),
                    isDense: true,
                    hintText: '비우면 자동 생성',
                  ),
                ),
                const SizedBox(height: 12),
                // 전화번호
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: '전화번호',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                // 유입경로
                const Text('유입경로', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  children: sourceOptions.map((s) {
                    final selected = editSource == s;
                    return ChoiceChip(
                      label: Text(s, style: const TextStyle(fontSize: 12)),
                      selected: selected,
                      onSelected: (_) => setS(() => editSource = s),
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                // 회원유형
                const Text('회원유형', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 4),
                SegmentedButton<String>(
                  segments: memberTypeOptions
                      .map((t) => ButtonSegment(value: t, label: Text(t, style: const TextStyle(fontSize: 12))))
                      .toList(),
                  selected: {editMemberType},
                  onSelectionChanged: (s) => setS(() => editMemberType = s.first),
                ),
                const SizedBox(height: 12),
                // 방문 횟수
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: dayCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '주간 방문',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: nightCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '야간 방문',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 메모
                TextField(
                  controller: memoCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '메모',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final newDay = int.tryParse(dayCtrl.text.trim()) ?? _customer.dayVisitCount;
      final newNight = int.tryParse(nightCtrl.text.trim()) ?? _customer.nightVisitCount;
      final newVisitCount = newDay + newNight;
      final newPhone = phoneCtrl.text.trim().isNotEmpty ? phoneCtrl.text.trim() : _customer.phone;
      final newMemo = memoCtrl.text.trim();
      final customName = nameCtrl.text.trim();

      final name = customName.isNotEmpty
          ? customName
          : Customer.buildContactLabel(
              phone: newPhone,
              source: editSource,
              visitCount: newVisitCount,
              dayVisitCount: newDay,
              nightVisitCount: newNight,
              couponBalance: _customer.couponBalance,
              memo: newMemo.isNotEmpty ? newMemo : null,
            );

      final updated = await _service.updateCustomerProfile(
        customerId: _customer.id,
        name: name,
        memberType: editMemberType,
        customerSource: editSource,
        visitCount: newVisitCount,
        dayVisitCount: newDay,
        nightVisitCount: newNight,
      );

      // 전화번호/메모가 변경되었으면 별도 업데이트
      if (newPhone != _customer.phone) {
        await _service.updatePhone(_customer.id, newPhone);
      }
      if (newMemo != (_customer.memo ?? '')) {
        await _service.updateMemo(_customer.id, newMemo);
      }

      // 로컬 주소록 동기화
      final refreshed = await _service.getCustomer(_customer.id);
      if (refreshed != null) {
        await ContactSyncService.syncCustomer(refreshed);
        if (!mounted) return;
        setState(() => _customer = refreshed);
      } else {
        if (!mounted) return;
        setState(() => _customer = updated);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('고객 정보를 수정했습니다.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('수정에 실패했습니다. $e')),
      );
    }
  }

  Future<void> _deleteCustomer() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('\uACE0\uAC1D \uC0AD\uC81C'),
        content: Text(
          '${_customer.contactLabel} \uACE0\uAC1D \uC815\uBCF4\uB97C \uC0AD\uC81C\uD558\uC2DC\uACA0\uC2B5\uB2C8\uAE4C?\n\uBC29\uBB38 \uAE30\uB85D\uC740 \uD568\uAED8 \uC0AD\uC81C\uB418\uACE0 \uC608\uC57D\uC740 \uACE0\uAC1D \uC5F0\uACB0\uB9CC \uD574\uC81C\uB429\uB2C8\uB2E4.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('\uCDE8\uC18C'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('\uC0AD\uC81C'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _service.deleteCustomer(_customer.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('\uACE0\uAC1D \uC815\uBCF4\uB97C \uC0AD\uC81C\uD588\uC2B5\uB2C8\uB2E4.'),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('\uACE0\uAC1D \uC0AD\uC81C\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4. $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_customer.contactLabel),
        backgroundColor: colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '정보 수정',
            onPressed: _editCustomerInfo,
          ),
          IconButton(
            icon: const Icon(Icons.add_location_alt_outlined),
            tooltip: '방문 기록',
            onPressed: _addVisit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '고객 삭제',
            onPressed: _deleteCustomer,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '\uAE30\uBCF8 \uC815\uBCF4',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  const Divider(),
                  _InfoRow(
                    icon: Icons.person,
                    label: '\uC774\uB984',
                    value: _customer.contactLabel,
                  ),
                  _InfoRow(
                    icon: Icons.phone,
                    label: '\uC804\uD654\uBC88\uD638',
                    value: _customer.phone,
                  ),
                  _InfoRow(
                    icon: Icons.hub_outlined,
                    label: '\uC720\uC785\uACBD\uB85C',
                    value: _customer.effectiveSource,
                  ),
                  _InfoRow(
                    icon: Icons.workspace_premium_outlined,
                    label: '\uB4F1\uAE09',
                    value: _customer.visitGrade,
                  ),
                  _InfoRow(
                    icon: Icons.badge_outlined,
                    label: '\uD68C\uC6D0\uC720\uD615',
                    value: _customer.memberType,
                  ),
                  _InfoRow(
                    icon: Icons.check_circle_outline,
                    label: '\uCD1D \uBC29\uBB38',
                    value:
                        '${_customer.visitCount}\uD68C (\uC8FC\uAC04 ${_customer.dayVisitCount} / \uC57C\uAC04 ${_customer.nightVisitCount})',
                  ),
                  _InfoRow(
                    icon: Icons.calendar_today,
                    label: '\uB9C8\uC9C0\uB9C9 \uBC29\uBB38',
                    value: _customer.lastVisitDate != null
                        ? _dateFormat.format(_customer.lastVisitDate!)
                        : '-',
                  ),
                  _InfoRow(
                    icon: Icons.account_balance_wallet_outlined,
                    label: '\uCFE0\uD3F0',
                    value:
                        '${_wonFormat.format(_customer.couponBalance)}\uC6D0',
                    valueColor: _customer.couponBalance < 0
                        ? Colors.red
                        : Colors.green[700],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _chargeCoupon,
            icon: const Icon(Icons.account_balance_wallet_outlined),
            label: const Text('\uCFE0\uD3F0 \uCDA9\uC804'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: BorderSide(color: colorScheme.primary),
              foregroundColor: colorScheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '\uBA54\uBAA8',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                      if (!_isEditingMemo)
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          onPressed: () {
                            setState(() => _isEditingMemo = true);
                          },
                        ),
                    ],
                  ),
                  const Divider(),
                  if (_isEditingMemo) ...[
                    TextField(
                      controller: _memoController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: '\uBA54\uBAA8\uB97C \uC785\uB825\uD558\uC138\uC694',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            _memoController.text = _customer.memo ?? '';
                            setState(() => _isEditingMemo = false);
                          },
                          child: const Text('\uCDE8\uC18C'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _saveMemo,
                          child: const Text('\uC800\uC7A5'),
                        ),
                      ],
                    ),
                  ] else
                    Text(
                      _customer.memo?.isNotEmpty == true
                          ? _customer.memo!
                          : '\uBA54\uBAA8 \uC5C6\uC74C',
                      style: TextStyle(
                        color: _customer.memo?.isNotEmpty == true
                            ? null
                            : Colors.grey,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '\uBC29\uBB38 \uC774\uB825',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  const Divider(),
                  if (_isLoadingHistory)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_history.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        '\uBC29\uBB38 \uC774\uB825\uC774 \uC5C6\uC2B5\uB2C8\uB2E4',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  else
                    ...List.generate(_history.length, (index) {
                      final history = _history[index];
                      final isDay = history.visitType == '\uC8FC\uAC04';
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: colorScheme.primaryContainer,
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        title: Text(
                          history.serviceName.isNotEmpty
                              ? history.serviceName
                              : _dateFormat.format(history.visitDate),
                        ),
                        subtitle: Text(
                          history.serviceName.isNotEmpty
                              ? _dateFormat.format(history.visitDate)
                              : '',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (history.servicePrice > 0)
                              Text(
                                '${_wonFormat.format(history.servicePrice)}\uC6D0',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey,
                                ),
                              ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isDay
                                    ? Colors.blue.withValues(alpha: 0.12)
                                    : Colors.deepPurple.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                history.visitType,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isDay
                                      ? Colors.blue[700]
                                      : Colors.deepPurple[400],
                                ),
                              ),
                            ),
                            PopupMenuButton<String>(
                              iconSize: 18,
                              padding: EdgeInsets.zero,
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _editVisitHistory(history);
                                } else if (value == 'delete') {
                                  _deleteVisitHistory(history);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit_outlined, size: 16),
                                      SizedBox(width: 8),
                                      Text('\uC218\uC815'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete_outline, size: 16, color: Colors.red),
                                      SizedBox(width: 8),
                                      Text('\uC0AD\uC81C', style: TextStyle(color: Colors.red)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  const _ConfirmRow(this.label, this.value, {this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
