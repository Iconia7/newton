import 'package:flutter/material.dart';
import 'package:newton/pages/Settings.dart';
import 'package:newton/pages/home_page.dart';
import 'package:newton/pages/manualussd.dart';

class MainWrapper extends StatefulWidget {
  final String userId;
  const MainWrapper({super.key, required this.userId});

  @override
  State<MainWrapper> createState() => _MainWrapperState();
}

class _MainWrapperState extends State<MainWrapper> {
  int _currentIndex = 0;
  static const Color snowWhite = Color(0xFFFCF7F8);
  static const Color madderRed = Color.fromARGB(0, 19, 106, 133);

  final List<Widget> _pages = [
    const HomeContent(userId: '',), // Your existing home content
    const ManualUssdTriggerPage(),
    const SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        selectedItemColor: madderRed,
        unselectedItemColor: snowWhite,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.phone),
            label: 'USSD',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}