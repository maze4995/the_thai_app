import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/customer.dart';

class IncomingCallOverlay extends StatefulWidget {
  const IncomingCallOverlay({
    super.key,
    required this.customerFuture,
    required this.phoneNumber,
    required this.onClose,
    required this.onViewCard,
  });

  final Future<Customer?> customerFuture;
  final String phoneNumber;
  final VoidCallback onClose;
  final VoidCallback onViewCard;

  @override
  State<IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends State<IncomingCallOverlay> {
  Customer? _customer;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    widget.customerFuture.then((customer) {
      if (!mounted) return;
      setState(() {
        _customer = customer;
        _loaded = true;
      });
    }).catchError((_) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final balanceFmt = NumberFormat('#,###', 'ko_KR');
    final isRegistered = _loaded && _customer != null;

    return Material(
      elevation: 8,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      color: const Color(0xFF3E2723),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.call, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: !_loaded
                    ? _LoadingInfo(phoneNumber: widget.phoneNumber)
                    : isRegistered
                        ? _RegisteredInfo(
                            customer: _customer!,
                            balanceFmt: balanceFmt,
                          )
                        : _UnregisteredInfo(phoneNumber: widget.phoneNumber),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: widget.onViewCard,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.amber,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      isRegistered
                          ? '\uACE0\uAC1D \uCE74\uB4DC'
                          : '\uC2E0\uADDC \uB4F1\uB85D',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onClose,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white54,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('\uB2EB\uAE30', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingInfo extends StatelessWidget {
  const _LoadingInfo({required this.phoneNumber});

  final String phoneNumber;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '\uD83D\uDCDE \uC218\uC2E0 \uC804\uD654',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        Text(
          phoneNumber,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 4),
        const SizedBox(
          width: 60,
          height: 4,
          child: LinearProgressIndicator(
            backgroundColor: Colors.white24,
            color: Colors.amber,
          ),
        ),
      ],
    );
  }
}

class _RegisteredInfo extends StatelessWidget {
  const _RegisteredInfo({required this.customer, required this.balanceFmt});

  final Customer customer;
  final NumberFormat balanceFmt;

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(color: Colors.white, fontSize: 13);
    const subStyle =
        TextStyle(color: Colors.white70, fontSize: 12, height: 1.5);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '\uD83D\uDCDE ${customer.name}',
          style: textStyle.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        Text(
          customer.visitCount > 0
              ? '\uBC29\uBB38 ${customer.visitCount}\uD68C (\uC8FC\uAC04 ${customer.dayVisitCount} / \uC57C\uAC04 ${customer.nightVisitCount})'
              : '\uBC29\uBB38 \uAE30\uB85D \uC5C6\uC74C',
          style: subStyle,
        ),
        Text(
          '\uCFE0\uD3F0 \uC794\uC561: ${balanceFmt.format(customer.couponBalance)}\uC6D0',
          style: subStyle.copyWith(
            color: customer.couponBalance < 0 ? Colors.red[300] : Colors.white70,
          ),
        ),
        if (customer.memo != null && customer.memo!.isNotEmpty)
          Text('\uBA54\uBAA8: ${customer.memo}', style: subStyle),
      ],
    );
  }
}

class _UnregisteredInfo extends StatelessWidget {
  const _UnregisteredInfo({required this.phoneNumber});

  final String phoneNumber;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '\uD83D\uDCDE \uBBF8\uB4F1\uB85D \uACE0\uAC1D',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        Text(
          phoneNumber,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ],
    );
  }
}

class PostCallBottomSheet extends StatelessWidget {
  const PostCallBottomSheet({
    super.key,
    required this.onYes,
    required this.onNo,
  });

  final VoidCallback onYes;
  final VoidCallback onNo;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '\uC608\uC57D\uC744 \uBC1B\uC73C\uC168\uB098\uC694?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onNo,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('\uC544\uB2C8\uC694'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onYes,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B4513),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('\uC608'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
