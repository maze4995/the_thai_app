import 'package:flutter/material.dart';

import '../app_config.dart';
import '../services/contact_sync_service.dart';
import '../services/supabase_service.dart';

class CustomerAddScreen extends StatefulWidget {
  const CustomerAddScreen({super.key, this.initialPhone});

  final String? initialPhone;

  @override
  State<CustomerAddScreen> createState() => _CustomerAddScreenState();
}

class _CustomerAddScreenState extends State<CustomerAddScreen> {
  static const _sources = [
    '\uB85C\uB4DC',
    '\uB9C8\uD1B5',
    '\uB9C8\uB9F5',
    '\uD558\uC774',
    '\uAE30\uC874',
    '\uBC34\uB4DC',
  ];

  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _memoController = TextEditingController();
  final _service = SupabaseService();

  String _customerSource = '\uB85C\uB4DC';
  bool _isSaving = false;

  String get _memberType => _customerSource == '\uB85C\uB4DC'
      ? '\uB85C\uB4DC\uD68C\uC6D0'
      : '\uC5B4\uD50C\uD68C\uC6D0';

  String _buildPreviewLabel() {
    final digits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    final suffix =
        digits.length >= 4 ? digits.substring(digits.length - 4) : digits;
    return '${AppConfig.contactPrefix}-New-$_customerSource(0)(0)$suffix';
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialPhone != null) {
      _phoneController.text = widget.initialPhone!;
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final customer = await _service.addCustomer(
        name: _buildPreviewLabel(),
        phone: _phoneController.text.trim(),
        memberType: _memberType,
        customerSource: _customerSource,
        memo: _memoController.text.trim().isEmpty
            ? null
            : _memoController.text.trim(),
      );
      await ContactSyncService.syncCustomer(customer);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('\uC800\uC7A5\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('\uC2E0\uADDC \uACE0\uAC1D \uB4F1\uB85D'),
        backgroundColor: colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _phoneController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: '\uC804\uD654\uBC88\uD638 *',
                  prefixIcon: Icon(Icons.phone),
                  border: OutlineInputBorder(),
                  hintText: '010-0000-0000',
                ),
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '\uC804\uD654\uBC88\uD638\uB97C \uC785\uB825\uD574\uC8FC\uC138\uC694';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              InputDecorator(
                decoration: InputDecoration(
                  labelText: '\uC720\uC785 \uACBD\uB85C',
                  border: const OutlineInputBorder(),
                  helperText:
                      '\uB85C\uB4DC\uB97C \uC81C\uC678\uD55C \uBAA8\uB4E0 \uACBD\uB85C\uB294 \uC5B4\uD50C\uD68C\uC6D0\uC73C\uB85C \uCC98\uB9AC\uB429\uB2C8\uB2E4. \uD604\uC7AC \uD68C\uC6D0 \uC720\uD615: $_memberType',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _sources.map((source) {
                    final selected = _customerSource == source;
                    return ChoiceChip(
                      label: Text(source),
                      selected: selected,
                      onSelected: (_) {
                        setState(() => _customerSource = source);
                      },
                      selectedColor: colorScheme.primary,
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : null,
                        fontWeight: selected ? FontWeight.bold : null,
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: '\uACE0\uAC1D\uBA85 \uBBF8\uB9AC\uBCF4\uAE30',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.contacts_outlined),
                ),
                child: Text(
                  _buildPreviewLabel(),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _memoController,
                decoration: const InputDecoration(
                  labelText: '\uBA54\uBAA8',
                  prefixIcon: Icon(Icons.note),
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
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
                    : const Text(
                        '\uC800\uC7A5',
                        style: TextStyle(fontSize: 16),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
