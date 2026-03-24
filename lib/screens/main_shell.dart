import 'package:flutter/material.dart';

import 'coupon_customers_screen.dart';
import 'home_screen.dart';
import 'reservation_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  int _homeRefreshKey = 0;
  int _couponRefreshKey = 0;
  int _reservationRefreshKey = 0;

  void _onTap(int index) {
    setState(() {
      _index = index;
      switch (index) {
        case 0:
          _homeRefreshKey++;
          break;
        case 1:
          _couponRefreshKey++;
          break;
        case 2:
          _reservationRefreshKey++;
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          HomeScreen(key: ValueKey(_homeRefreshKey)),
          CouponCustomersScreen(key: ValueKey(_couponRefreshKey)),
          ReservationScreen(key: ValueKey(_reservationRefreshKey)),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: _onTap,
        selectedItemColor: const Color(0xFF8B4513),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            activeIcon: Icon(Icons.people),
            label: '\uACE0\uAC1D',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.card_giftcard_outlined),
            activeIcon: Icon(Icons.card_giftcard),
            label: '\uCFE0\uD3F0 \uACE0\uAC1D',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today_outlined),
            activeIcon: Icon(Icons.calendar_today),
            label: '\uC608\uC57D',
          ),
        ],
      ),
    );
  }
}
