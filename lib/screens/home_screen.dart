import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_route_observer.dart';
import '../models/customer.dart';
import '../services/auth_service.dart';
import '../services/contact_sync_service.dart';
import '../services/sms_service.dart';
import '../services/supabase_service.dart';
import 'customer_add_screen.dart';
import 'customer_detail_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.title = '고객',
    this.couponOnly = false,
    this.allowContactImport = true,
    this.showSmsSettings = false,
  });

  final String title;
  final bool couponOnly;
  final bool allowContactImport;
  final bool showSmsSettings;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with RouteAware {
  final _service = SupabaseService();
  final _searchController = TextEditingController();

  List<Customer> _customers = [];
  bool _isLoading = true;
  bool _isImportingContacts = false;
  bool _isExportingContacts = false;
  String _searchQuery = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  void didPopNext() {
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    setState(() => _isLoading = true);
    try {
      final customers = _searchQuery.isEmpty
          ? widget.couponOnly
              ? await _service.getCouponCustomers()
              : await _service.getCustomers()
          : widget.couponOnly
              ? await _service.searchCouponCustomers(_searchQuery)
              : await _service.searchCustomers(_searchQuery);
      if (!mounted) return;
      setState(() => _customers = customers);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('고객 목록을 불러오지 못했습니다. $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onSearchChanged(String value) {
    _searchQuery = value;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), _loadCustomers);
  }

  Future<void> _importContacts() async {
    try {
      final mode = await showDialog<ContactImportMode>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('가져오기 방식 선택'),
          content: const Text('주소록을 앱 DB에 어떻게 반영할지 선택하세요.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, ContactImportMode.addOnlyNew),
              child: const Text('없는 고객만 추가'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(ctx, ContactImportMode.overwriteAll),
              child: const Text('전체 덮어쓰기'),
            ),
          ],
        ),
      );
      if (!mounted || mode == null) return;

      var previewCurrent = 0;
      var previewTotal = 0;
      StateSetter? updatePreviewDialog;

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setStateDialog) {
            updatePreviewDialog = setStateDialog;
            final progress =
                previewTotal > 0 ? previewCurrent / previewTotal : null;
            return AlertDialog(
              title: const Text('주소록 분석 중'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    previewTotal > 0
                        ? '$previewCurrent / $previewTotal개 분석 중...'
                        : '주소록을 읽는 중...',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.grey[200],
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ],
              ),
            );
          },
        ),
      );

      final prepared = await ContactSyncService.prepareContactsImport(
        _service,
        mode: mode,
        onProgress: (current, total, _) {
          previewCurrent = current;
          previewTotal = total;
          updatePreviewDialog?.call(() {});
        },
      );
      final preview = prepared.preview;

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('주소록 가져오기'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                mode == ContactImportMode.overwriteAll
                    ? '모드: 전체 덮어쓰기'
                    : '모드: DB에 없는 고객만 추가',
              ),
              const SizedBox(height: 8),
              Text('신규 생성 예정: ${preview.toCreate}명'),
              Text('기존 갱신 예정: ${preview.toUpdate}명'),
              Text('건너뜀 예정: ${preview.toSkip}명'),
              const SizedBox(height: 12),
              const Text('이대로 가져오시겠습니까?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('가져오기'),
            ),
          ],
        ),
      );

      if (!mounted || confirmed != true) return;
      setState(() => _isImportingContacts = true);

      var importPhase = '';
      var importCurrent = 0;
      var importTotal = 0;
      StateSetter? updateImportDialog;

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setStateDialog) {
            updateImportDialog = setStateDialog;
            final (label, sublabel) = switch (importPhase) {
              'create' => (
                  '신규 고객 생성 중',
                  '$importCurrent / $importTotal명',
                ),
              'update' => (
                  '기존 고객 업데이트 중',
                  '$importCurrent / $importTotal명',
                ),
              'sync' => (
                  '주소록 동기화 중',
                  '$importCurrent / $importTotal건',
                ),
              _ => ('가져오는 중...', ''),
            };
            final progress =
                importTotal > 0 ? importCurrent / importTotal : null;
            return AlertDialog(
              title: const Text('주소록 가져오기'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 14)),
                  if (sublabel.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      sublabel,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.grey[200],
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ],
              ),
            );
          },
        ),
      );

      final summary = await ContactSyncService.importPreparedContactsToDatabase(
        _service,
        prepared,
        onProgress: (current, total, phase) {
          importPhase = phase;
          importCurrent = current;
          importTotal = total;
          updateImportDialog?.call(() {});
        },
      );

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      await _loadCustomers();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '주소록 가져오기 완료: 신규 ${summary.created}, 갱신 ${summary.updated}, 건너뜀 ${summary.skipped}',
          ),
        ),
      );
    } catch (e) {
      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('주소록 가져오기 실패: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isImportingContacts = false);
      }
    }
  }

  Future<void> _exportContacts() async {
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('주소록으로 내보내기'),
          content: const Text(
            '앱 DB의 고객 정보를 기준으로\n로컬 주소록의 이름을 덮어씁니다.\n로컬에 없는 고객은 새로 생성됩니다.\n\n계속하시겠습니까?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('내보내기'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;

      setState(() => _isExportingContacts = true);

      var exportCurrent = 0;
      var exportTotal = 0;
      StateSetter? updateDialog;

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setStateDialog) {
            updateDialog = setStateDialog;
            final progress = exportTotal > 0 ? exportCurrent / exportTotal : null;
            return AlertDialog(
              title: const Text('주소록으로 내보내기'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exportTotal > 0
                        ? '$exportCurrent / $exportTotal명 처리 중...'
                        : '데이터 불러오는 중...',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.grey[200],
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ],
              ),
            );
          },
        ),
      );

      final summary = await ContactSyncService.exportDatabaseToContacts(
        _service,
        onProgress: (current, total, _) {
          exportCurrent = current;
          exportTotal = total;
          updateDialog?.call(() {});
        },
      );

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '내보내기 완료: 신규 ${summary.created}, 갱신 ${summary.updated}, 건너뜀 ${summary.skipped}',
          ),
        ),
      );
    } catch (e) {
      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('내보내기 실패: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isExportingContacts = false);
      }
    }
  }

  Future<void> _editSmsTemplate() async {
    final target = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('문자 템플릿 선택'),
        content: const Text('수정할 문자 템플릿을 선택해주세요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('일반 차감'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('전액 소진'),
          ),
        ],
      ),
    );
    if (target == null || !mounted) return;

    final isDepletion = target;
    final current = isDepletion
        ? await SmsService.getDepletionTemplate()
        : await SmsService.getTemplate();
    if (!mounted) return;

    final ctrl = TextEditingController(text: current);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isDepletion ? '전액 소진 문자 편집' : '일반 차감 문자 편집'),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isDepletion
                    ? '치환 변수: [M/d], [service]'
                    : '치환 변수: [M/d], [service], [remaining]',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                maxLines: 6,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(
              ctx,
              isDepletion
                  ? SmsService.depletionTemplate
                  : SmsService.defaultTemplate,
            ),
            child: const Text('기본값'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (saved == null || !mounted) return;

    if (isDepletion) {
      await SmsService.saveDepletionTemplate(saved);
    } else {
      await SmsService.saveTemplate(saved);
    }
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isDepletion
              ? '전액 소진 문자 템플릿을 저장했습니다.'
              : '일반 차감 문자 템플릿을 저장했습니다.',
        ),
      ),
    );
  }

  Future<void> _navigateToAdd() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CustomerAddScreen()),
    );
    if (added == true) {
      _loadCustomers();
    }
  }

  Future<void> _navigateToDetail(Customer customer) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerDetailScreen(customer: customer),
      ),
    );
    _loadCustomers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          if (widget.showSmsSettings)
            IconButton(
              onPressed: _editSmsTemplate,
              tooltip: 'SMS 템플릿 편집',
              icon: const Icon(Icons.sms_outlined),
            ),
          if (widget.allowContactImport) ...[
            IconButton(
              onPressed: _isExportingContacts ? null : _exportContacts,
              tooltip: 'DB→주소록 내보내기',
              icon: _isExportingContacts
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.upload_outlined),
            ),
            IconButton(
              onPressed: _isImportingContacts ? null : _importContacts,
              tooltip: '주소록→DB 가져오기',
              icon: _isImportingContacts
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.download_outlined),
            ),
          ],
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value == 'logout') {
                await AuthService.signOut();
                if (!mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => LoginScreen(
                      onLoginSuccess: () {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const MainShell()),
                          (_) => false,
                        );
                      },
                    ),
                  ),
                  (_) => false,
                );
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    const Icon(Icons.logout, size: 18, color: Colors.red),
                    const SizedBox(width: 8),
                    const Text('로그아웃', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: '이름 또는 전화번호 검색',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
          if (!_isLoading)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 4),
              child: Text(
                _searchQuery.isEmpty
                    ? '전체 ${_customers.length}명'
                    : '검색 결과 ${_customers.length}명',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _customers.isEmpty
                    ? Center(
                        child: Text(
                          widget.couponOnly ? '쿠폰 고객이 없습니다' : '고객이 없습니다',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadCustomers,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _customers.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final customer = _customers[index];
                            return _CustomerTile(
                              customer: customer,
                              onTap: () => _navigateToDetail(customer),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToAdd,
        tooltip: '신규 고객 등록',
        child: const Icon(Icons.person_add),
      ),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  const _CustomerTile({required this.customer, required this.onTap});

  final Customer customer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final wonFormat = NumberFormat('#,###', 'ko_KR');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Text(
          customer.contactLabel.isNotEmpty ? customer.contactLabel[0] : '?',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(
        customer.contactLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 2),
          Text(customer.phone),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Badge(
                icon: Icons.check_circle_outline,
                label: customer.visitGrade,
                color: Colors.blue,
              ),
              _Badge(
                icon: Icons.hub_outlined,
                label: customer.effectiveSource,
                color: Colors.brown,
              ),
              _Badge(
                icon: Icons.account_balance_wallet_outlined,
                label: '${wonFormat.format(customer.couponBalance)}원',
                color: customer.couponBalance < 0 ? Colors.red : Colors.orange,
              ),
            ],
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (customer.visitCount > 0)
            Text(
              '주간 ${customer.dayVisitCount} / 야간 ${customer.nightVisitCount}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
        ],
      ),
      isThreeLine: true,
      minVerticalPadding: 10,
      onTap: onTap,
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 2),
          Text(label, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}
