
import 'package:flutter/material.dart';
import 'talk_page.dart';
import 'matches_page.dart';
import 'profile_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
	final int initialIndex;
	const HomePage({ Key? key, this.initialIndex = 0 }) : super(key: key);
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {

  late int _selectedIndex;
  bool _showTutorial = false;
  List<Widget> _pages = [];

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _checkTutorialStatus();
  }

  Future<void> _checkTutorialStatus() async {
    // Temporarily always show tutorial for testing
    setState(() {
      _showTutorial = true;
      _pages = [
        TalkPage(showTutorial: _showTutorial),
        MatchesPage(),
        ProfilePage(),
      ];
    });
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(
              color: Colors.grey.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            height: 60,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(
                  index: 0,
                  icon: Icons.mic_rounded,
                  label: 'Talk',
                ),
                _buildNavItem(
                  index: 1,
                  icon: Icons.favorite_rounded,
                  label: 'Matches',
                ),
                _buildNavItem(
                  index: 2,
                  icon: Icons.person_rounded,
                  label: 'Profile',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _selectedIndex == index;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onItemTapped(index),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 24,
                  color: isSelected
                      ? const Color(0xFF985021)
                      : Colors.grey.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected
                        ? const Color(0xFF985021)
                        : Colors.grey.withValues(alpha: 0.6),
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


