import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MainScaffold extends StatelessWidget {
  final int selectedIndex;
  final Widget body;

  const MainScaffold({
    super.key,
    required this.selectedIndex,
    required this.body,
  });

  String getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return "Good morning";
    if (hour < 17) return "Good afternoon";
    return "Good evening";
  }

  void _onItemTapped(BuildContext context, int index) {
    if (index == 0) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        context.go('/login');
      }
    } else if (index == 1) {
      context.go('/home');
    } else if (index == 2) {
      _confirmLogout(context); // Logout with confirmation

    }
  }
  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(dialogContext).pop(); // Close dialog
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Logout'),
              onPressed: () {
                Navigator.of(dialogContext).pop(); // Close dialog
               
                context.go('/login');
                // Or run logout logic here
              },
            ),
          ],
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(90),
        child: Material(
          elevation: 4,
          shadowColor: Colors.black45,
          color: Colors.white,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.01),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: SafeArea(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  InkWell(
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Profile tapped')),
                      );
                    },
                    borderRadius: BorderRadius.circular(30),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          radius: 20,
                          backgroundImage: AssetImage('assets/images/profile.png'),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${getGreeting()},',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                            const Text(
                              'Badrul',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Wallet tapped')),
                      );
                    },
                    borderRadius: BorderRadius.circular(30),
                    child: Row(
                      children: [
                        Icon(Icons.account_balance_wallet, color: Colors.orange[700]),
                        const SizedBox(width: 6),
                        Text(
                          'Credit : 200',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange[800],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: body,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: selectedIndex,
          onTap: (index) => _onItemTapped(context, index),
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: theme.primaryColor,
          unselectedItemColor: Colors.grey[500],
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.arrow_back),
              label: 'Back',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.home_filled),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.logout_rounded),
              label: 'Logout',
            ),
          ],
        ),
      ),
    );
  }
}
