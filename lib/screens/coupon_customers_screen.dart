import 'home_screen.dart';

class CouponCustomersScreen extends HomeScreen {
  const CouponCustomersScreen({super.key})
      : super(
          title: '쿠폰 고객',
          couponOnly: true,
          allowContactImport: false,
          showSmsSettings: true,
        );
}
