import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/service_menu.dart';
import '../models/reservation.dart';
import '../services/contact_sync_service.dart';
import '../services/supabase_service.dart';
import 'reservation_add_screen.dart';

class ReservationScreen extends StatefulWidget {
  const ReservationScreen({super.key});

  @override
  State<ReservationScreen> createState() => _ReservationScreenState();
}

class _ReservationScreenState extends State<ReservationScreen> {
  final _service = SupabaseService();
  final _dateFmt = DateFormat('yyyy\uB144 M\uC6D4 d\uC77C (E)', 'ko_KR');

  DateTime _selectedDate = _today();
  List<Reservation> _reservations = [];
  bool _isLoading = true;

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final list = await _service.getReservationsByDate(_selectedDate);
      if (!mounted) return;
      setState(() => _reservations = list);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('\uC608\uC57D\uC744 \uBD88\uB7EC\uC624\uC9C0 \uBABB\uD588\uC2B5\uB2C8\uB2E4. $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _load();
    }
  }

  void _shiftDate(int days) {
    setState(() => _selectedDate = _selectedDate.add(Duration(days: days)));
    _load();
  }

  Future<void> _handleCancel(Reservation reservation) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('\uC608\uC57D \uCDE8\uC18C'),
        content: Text('${reservation.customerName} \uC608\uC57D\uC744 \uCDE8\uC18C\uD558\uC2DC\uACA0\uC2B5\uB2C8\uAE4C?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('\uB2EB\uAE30'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              '\uCDE8\uC18C \uCC98\uB9AC',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final updated = await _service.updateReservationStatus(
        reservation.id,
        '\uCDE8\uC18C',
      );
      if (updated != null) {
        await ContactSyncService.syncCustomer(updated);
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('\uCDE8\uC18C \uCC98\uB9AC\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4. $e')),
      );
    }
  }

  Future<void> _handleNoShow(Reservation reservation) async {
    int? deductAmount;
    if (reservation.customerId != null && reservation.serviceName != null) {
      final customer = await _service.getCustomer(reservation.customerId!);
      if (customer != null) {
        final services = kServiceMenu[customer.memberType] ?? [];
        final match = services.cast<dynamic>().firstWhere(
              (service) => service.name == reservation.serviceName,
              orElse: () => null,
            );
        if (match != null && match.price > 0) {
          deductAmount = match.price as int;
        }
      }
    }

    if (!mounted) return;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('\uB178\uC1FC \uCC98\uB9AC'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${reservation.customerName} \uC608\uC57D\uC744 \uB178\uC1FC \uCC98\uB9AC\uD558\uC2DC\uACA0\uC2B5\uB2C8\uAE4C?'),
            if (deductAmount != null) ...[
              const SizedBox(height: 12),
              Text(
                '\uCFE0\uD3F0 ${NumberFormat('#,###', 'ko_KR').format(deductAmount)}\uC6D0\uC744 \uCC28\uAC10\uD560\uAE4C\uC694?',
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('\uB2EB\uAE30'),
          ),
          if (deductAmount != null)
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, 'no_deduct'),
              child: const Text('\uCC28\uAC10 \uC5C6\uC774 \uB178\uC1FC'),
            ),
          ElevatedButton(
            onPressed: () => Navigator.pop(
              ctx,
              deductAmount != null ? 'deduct' : 'noshow',
            ),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: Text(
              deductAmount != null
                  ? '\uCC28\uAC10\uD558\uACE0 \uB178\uC1FC'
                  : '\uB178\uC1FC',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (result == null || result == 'cancel') return;

    try {
      final doDeduct = result == 'deduct' && deductAmount != null;
      final updated = await _service.updateReservationStatus(
        reservation.id,
        '\uB178\uC1FC',
        couponUsed: doDeduct ? deductAmount : null,
      );
      if (doDeduct) {
        await _service.deductCouponForNoShow(
          reservation.customerId!,
          deductAmount,
        );
      }
      if (updated != null) {
        await ContactSyncService.syncCustomer(updated);
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('\uB178\uC1FC \uCC98\uB9AC\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4. $e')),
      );
    }
  }

  Future<void> _handleEdit(Reservation reservation) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ReservationAddScreen(initialReservation: reservation),
      ),
    );
    _load();
  }

  Future<void> _handleDelete(Reservation reservation) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('\uC608\uC57D \uC0AD\uC81C'),
        content: Text('${reservation.customerName} \uC608\uC57D \uB0B4\uC5ED\uC744 \uC0AD\uC81C\uD558\uC2DC\uACA0\uC2B5\uB2C8\uAE4C?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('\uB2EB\uAE30'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('\uC0AD\uC81C'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final updated = await _service.deleteReservation(reservation.id);
      if (updated != null) {
        await ContactSyncService.syncCustomer(updated);
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('\uC608\uC57D \uC0AD\uC81C\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4. $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isToday = _selectedDate == _today();

    return Scaffold(
      appBar: AppBar(
        title: const Text('\uC608\uC57D'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '\uC608\uC57D \uCD94\uAC00',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ReservationAddScreen(initialDate: _selectedDate),
                ),
              );
              _load();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Theme.of(context).colorScheme.primaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _shiftDate(-1),
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: _pickDate,
                    child: Column(
                      children: [
                        Text(
                          _dateFmt.format(_selectedDate),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                        ),
                        if (isToday)
                          Text(
                            '\uC624\uB298',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _shiftDate(1),
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _reservations.isEmpty
                    ? Center(
                        child: Text(
                          '\uC608\uC57D\uC774 \uC5C6\uC2B5\uB2C8\uB2E4',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _reservations.length,
                          itemBuilder: (_, index) => _ReservationCard(
                            reservation: _reservations[index],
                            onEdit: () => _handleEdit(_reservations[index]),
                            onCancel: () => _handleCancel(_reservations[index]),
                            onNoShow: () => _handleNoShow(_reservations[index]),
                            onDelete: () => _handleDelete(_reservations[index]),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _ReservationCard extends StatelessWidget {
  const _ReservationCard({
    required this.reservation,
    required this.onEdit,
    required this.onCancel,
    required this.onNoShow,
    required this.onDelete,
  });

  final Reservation reservation;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final VoidCallback onNoShow;
  final VoidCallback onDelete;

  int? _servicePriceForReservation() {
    if (reservation.serviceName == null) return null;
    final menus = kServiceMenu.values.toList();
    if (menus.isEmpty) return null;

    final useRoadMenu = reservation.source == '\uB85C\uB4DC' ||
        reservation.customerName.contains('\uB85C\uB4DC');
    final menuIndex = useRoadMenu ? 0 : (menus.length > 1 ? 1 : 0);

    for (final service in menus[menuIndex]) {
      if (service.name == reservation.serviceName) return service.price;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isConfirmed = reservation.status == '\uC608\uC57D\uD655\uC815';
    final servicePrice = _servicePriceForReservation();
    final requiresAdditionalPayment = servicePrice != null &&
        reservation.couponUsed > 0 &&
        servicePrice > reservation.couponUsed;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  reservation.reservedTime,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 10),
                _SourceBadge(reservation.source),
                const SizedBox(width: 6),
                _StatusBadge(reservation.status),
                if (reservation.couponUsed > 0) ...[
                  const SizedBox(width: 6),
                  const _Badge(label: '\uCFE0\uD3F0\uACE0\uAC1D', color: Colors.deepPurple),
                ],
                if (requiresAdditionalPayment) ...[
                  const SizedBox(width: 6),
                  const _Badge(
                    label: '\uCD94\uAC00\uACB0\uC81C\uD544\uC694',
                    color: Colors.red,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              reservation.customerName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Text(
              reservation.customerPhone,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            if (reservation.serviceName != null) ...[
              const SizedBox(height: 2),
              Text(
                reservation.serviceName!,
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
            ],
            if (reservation.memo case final memo? when memo.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                '\uBA54\uBAA8: $memo',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isConfirmed) ...[
                  OutlinedButton(
                    onPressed: onEdit,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                      side: const BorderSide(color: Colors.blue),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('수정', style: TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: onCancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('\uCDE8\uC18C', style: TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: onNoShow,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange,
                      side: const BorderSide(color: Colors.orange),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('\uB178\uC1FC', style: TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                ],
                OutlinedButton(
                  onPressed: onDelete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey[700],
                    side: BorderSide(color: Colors.grey[400]!),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('\uC0AD\uC81C', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge(this.source);

  final String source;

  @override
  Widget build(BuildContext context) {
    final color = switch (source) {
      '\uB9C8\uD1B5' => Colors.purple,
      '\uD558\uC774\uD0C0\uC774' => Colors.teal,
      '\uB9C8\uB9F5' => Colors.green,
      '\uB85C\uB4DC' => Colors.blueGrey,
      '\uBC34\uB4DC' => Colors.indigo,
      _ => Colors.blue,
    };
    return _Badge(label: source, color: color);
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.status);

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      '\uCDE8\uC18C' => Colors.grey,
      '\uB178\uC1FC' => Colors.red,
      _ => const Color(0xFF8B4513),
    };
    return _Badge(label: status, color: color);
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
