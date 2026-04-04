import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'app_route_observer.dart';
import 'models/customer.dart';
import 'screens/customer_add_screen.dart';
import 'screens/customer_detail_screen.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'screens/reservation_add_screen.dart';
import 'services/auth_service.dart';
import 'services/native_call_service.dart';
import 'services/notification_service.dart';
import 'services/phone_service.dart';
import 'services/supabase_service.dart';
import 'widgets/incoming_call_overlay.dart';

final _navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko_KR');
  AppConfig.validate();
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );
  runApp(const ThaiApp());
}

class ThaiApp extends StatefulWidget {
  const ThaiApp({super.key});

  @override
  State<ThaiApp> createState() => _ThaiAppState();
}

class _ThaiAppState extends State<ThaiApp> with WidgetsBindingObserver {
  final _supabase = SupabaseService();
  final _balanceFmt = NumberFormat('#,###', 'ko_KR');

  bool _isInForeground = true;
  OverlaySupportEntry? _callOverlayEntry;
  Customer? _lastCallerCustomer;
  String? _lastCallerPhone;
  bool _hadIncomingCall = false;
  DateTime? _lastCallEndedAt;
  String? _pendingAction;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    await NotificationService.initialize(_onNotificationResponse);
    await Permission.notification.request();
    await Permission.ignoreBatteryOptimizations.request();
    await _checkNativePendingCall();

    final granted = await PhoneService.instance.initialize();
    if (granted) {
      PhoneService.instance.events.listen(_onCallEvent);
    }
  }

  Future<void> _checkNativePendingCall() async {
    final pending = await NativeCallService.getPendingCall();
    if (pending == null) return;

    final number = pending['number'] ?? '';
    final state = pending['state'] ?? '';
    final action = pending['action'] ?? '';

    _lastCallerPhone = number.isNotEmpty ? number : null;
    _lastCallerCustomer =
        number.isNotEmpty ? await _supabase.findCustomerByPhone(number) : null;

    await NativeCallService.clearPendingCall();

    Future.microtask(() {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final displayPhone = number.isNotEmpty
            ? PhoneService.format(number)
            : '\uBC88\uD638 \uC5C6\uC74C';

        if (state == 'incoming') {
          _callOverlayEntry?.dismiss();
          _callOverlayEntry = showOverlayNotification(
            (context) => IncomingCallOverlay(
              customerFuture: Future.value(_lastCallerCustomer),
              phoneNumber: displayPhone,
              onClose: () => _callOverlayEntry?.dismiss(),
              onViewCard: () {
                _callOverlayEntry?.dismiss();
                _navigateToCard();
              },
            ),
            duration: Duration.zero,
            position: NotificationPosition.top,
          );
        } else if (state == 'ended') {
          if (action == 'view_card') {
            _navigateToReservation();
          } else {
            _showPostCallSheet();
          }
        }
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PhoneService.instance.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isInForeground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed && _pendingAction != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _executePendingAction();
      });
    }
  }

  void _onNotificationResponse(String? actionId) {
    if (actionId == 'no') {
      NotificationService.cancelAll();
      return;
    }

    NotificationService.cancelAll();
    _pendingAction = actionId == 'yes' ? 'reservation' : 'sheet';

    if (_isInForeground) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _executePendingAction();
      });
    }
  }

  void _executePendingAction() {
    final action = _pendingAction;
    _pendingAction = null;
    if (action == 'reservation') {
      _navigateToReservation();
    } else if (action == 'sheet') {
      _showPostCallSheet();
    }
  }

  Future<void> _onCallEvent(PhoneCallEvent event) async {
    if (event.type == PhoneCallEventType.incoming) {
      final phone = event.phoneNumber ?? '';
      _lastCallerPhone = phone;
      _hadIncomingCall = true;

      final displayPhone = phone.isNotEmpty
          ? PhoneService.format(phone)
          : '\uBC88\uD638 \uC5C6\uC74C';

      if (_isInForeground) {
        final lookupFuture = phone.isNotEmpty
            ? _supabase.findCustomerByPhone(phone)
            : Future<Customer?>.value(null);
        lookupFuture.then((customer) => _lastCallerCustomer = customer);

        _callOverlayEntry?.dismiss();
        _callOverlayEntry = showOverlayNotification(
          (context) => IncomingCallOverlay(
            customerFuture: lookupFuture,
            phoneNumber: displayPhone,
            onClose: () => _callOverlayEntry?.dismiss(),
            onViewCard: () {
              _callOverlayEntry?.dismiss();
              _navigateToCard();
            },
          ),
          duration: Duration.zero,
          position: NotificationPosition.top,
        );
      } else {
        _lastCallerCustomer = phone.isNotEmpty
            ? await _supabase.findCustomerByPhone(phone)
            : null;
        final customer = _lastCallerCustomer;

        await NotificationService.showIncomingCall(
          title: customer != null
              ? '\uD83D\uDCDE ${customer.name}'
              : '\uD83D\uDCDE \uBBF8\uB4F1\uB85D \uACE0\uAC1D $displayPhone',
          body: customer != null
              ? '\uBC29\uBB38 ${customer.visitCount}\uD68C, \uCFE0\uD3F0 ${_balanceFmt.format(customer.couponBalance)}\uC6D0'
              : '\uACE0\uAC1D \uC815\uBCF4\uB97C \uD655\uC778\uD574\uBCF4\uC138\uC694',
        );
      }
    } else if (event.type == PhoneCallEventType.ended) {
      _callOverlayEntry?.dismiss();
      _callOverlayEntry = null;

      if (!_hadIncomingCall) return;
      _hadIncomingCall = false;
      _lastCallEndedAt = DateTime.now();

      if (_isInForeground) {
        _showPostCallSheet();
      } else {
        await NotificationService.cancelIncoming();
        final customer = _lastCallerCustomer;
        await NotificationService.showPostCall(
          title: customer != null
              ? '${customer.name} \uD1B5\uD654 \uC885\uB8CC'
              : '\uD1B5\uD654 \uC885\uB8CC',
          body: '\uC608\uC57D\uC744 \uBC1B\uC73C\uC168\uB098\uC694?',
        );
      }
    }
  }

  void _navigateToCard() {
    final nav = _navigatorKey.currentState;
    if (nav == null) return;

    if (_lastCallerCustomer != null) {
      nav.push(
        MaterialPageRoute(
          builder: (_) => CustomerDetailScreen(customer: _lastCallerCustomer!),
        ),
      );
    } else {
      final formatted = _lastCallerPhone != null && _lastCallerPhone!.isNotEmpty
          ? PhoneService.format(_lastCallerPhone!)
          : null;
      nav.push(
        MaterialPageRoute(
          builder: (_) => CustomerAddScreen(initialPhone: formatted),
        ),
      );
    }
  }

  Future<void> _navigateToReservation() async {
    final nav = _navigatorKey.currentState;
    if (nav == null) return;

    Customer? customer = _lastCallerCustomer;
    final phone = _lastCallerPhone;
    if (customer == null && phone != null && phone.isNotEmpty) {
      customer = await _supabase.findCustomerByPhone(phone);
      _lastCallerCustomer = customer;
    }

    final formatted =
        phone != null && phone.isNotEmpty ? PhoneService.format(phone) : null;

    if (!mounted) return;
    nav.push(
      MaterialPageRoute(
        builder: (_) => ReservationAddScreen(
          initialCustomer: customer,
          initialPhone: customer == null ? formatted : null,
          initialDate: _lastCallEndedAt,
          initialTime: _lastCallEndedAt != null
              ? TimeOfDay.fromDateTime(_lastCallEndedAt!)
              : null,
          initialSource: customer != null
              ? switch (customer.effectiveSource) {
                  '\uD558\uC774' => '\uD558\uC774\uD0C0\uC774',
                  '\uB9C8\uD1B5' => '\uB9C8\uD1B5',
                  '\uB9C8\uB9F5' => '\uB9C8\uB9F5',
                  '\uB85C\uB4DC' => '\uB85C\uB4DC',
                  '\uBC34\uB4DC' => '\uBC34\uB4DC',
                  _ => '\uAE30\uC874',
                }
              : '\uAE30\uC874',
        ),
      ),
    );
  }

  void _showPostCallSheet() {
    final nav = _navigatorKey.currentState;
    if (nav == null) return;

    showModalBottomSheet(
      context: nav.context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => PostCallBottomSheet(
        onYes: () {
          Navigator.pop(sheetContext);
          _navigateToReservation();
        },
        onNo: () => Navigator.pop(sheetContext),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OverlaySupport.global(
      child: MaterialApp(
        title: AppConfig.appTitle,
        debugShowCheckedModeBanner: false,
        navigatorKey: _navigatorKey,
        navigatorObservers: [routeObserver],
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF8B4513),
          ),
          useMaterial3: true,
        ),
        home: const _AuthGate(),
      ),
    );
  }
}

// ── 인증 게이트 ──────────────────────────────────────────────────────────────

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _loading = true;
  bool _authenticated = false;
  late final StreamSubscription<AuthState> _authSub;

  @override
  void initState() {
    super.initState();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      final event = data.event;

      if (event == AuthChangeEvent.signedIn ||
          event == AuthChangeEvent.tokenRefreshed ||
          event == AuthChangeEvent.initialSession) {
        if (session != null) {
          _handleAuthenticated();
        } else if (event == AuthChangeEvent.initialSession) {
          // 저장된 세션이 없는 경우
          if (mounted) setState(() { _loading = false; _authenticated = false; });
        }
      } else if (event == AuthChangeEvent.signedOut) {
        if (mounted) setState(() { _loading = false; _authenticated = false; });
      }
    });
  }

  Future<void> _handleAuthenticated() async {
    if (AuthService.storeId == null) {
      await AuthService.loadStoreId();
    }
    if (mounted) setState(() { _loading = false; _authenticated = true; });
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }

  void _onLoginSuccess() {
    setState(() => _authenticated = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF1a1a2e),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF8B4513)),
        ),
      );
    }
    if (!_authenticated) {
      return LoginScreen(onLoginSuccess: _onLoginSuccess);
    }
    return const MainShell();
  }
}
