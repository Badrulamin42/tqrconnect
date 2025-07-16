import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:dio/dio.dart';

class MainScaffold extends StatefulWidget {
  final int selectedIndex;
  final Widget body;
  final VoidCallback? onOutletChanged; // ✅ Add this line


  const MainScaffold({
    super.key,
    required this.selectedIndex,
    required this.body,
    this.onOutletChanged, // ✅ Also add it here
  });

  @override
  State<MainScaffold> createState() => MainScaffoldState();
}


class MainScaffoldState extends State<MainScaffold> {
  final _storage = const FlutterSecureStorage();
  String? fullName;
  String? outletName;
  int credit = 0;
  final Dio dio = Dio();

  @override
  void initState() {
    super.initState();
    _checkAndSelectOutlet();
    _loadUserFullName();
    _loadUserAndOutletInfo();
  }

  Future<void> _loadUserFullName() async {
    final name = await _storage.read(key: 'user_fullname');
    setState(() {
      fullName = name ?? 'User'; // Fallback if not found
    });
  }

  Future<void> refreshCredit() async {
    final outletJson = await _storage.read(key: 'selected_outlet');
    if (outletJson == null) return;

    final outlet = jsonDecode(outletJson);
    final outletUserId = outlet['Id']; // 👈 assuming this is OutletUser Id

    // Call your backend API to get the latest credit
    final response = await dio.get(
      'https://192.168.0.203/api/mobile/outlet-user/$outletUserId/credit',
      options: Options(
        headers: {
          'Authorization': 'Bearer ${await _storage.read(key: 'auth_token')}',
        },
      ),
    );

    final newCredit = response.data['credit'];
    print('response credit : $response');
    setState(() {
      credit = newCredit;
    });
  }

  Future<void> _checkAndSelectOutlet() async {
    final selected = await _storage.read(key: 'selected_outlet');
    if (selected == null) {
      await _handleOutletSelection(context);
    }
  }
  Future<void> _loadUserAndOutletInfo() async {
    final storage = FlutterSecureStorage();
    final name = await storage.read(key: 'user_fullname');
    final outletJson = await storage.read(key: 'selected_outlet');

    setState(() {
      fullName = name;
    });

    if (outletJson != null) {
      final outlet = jsonDecode(outletJson);
      setState(() {
        outletName = outlet['Outlet']?['Name'] ?? '';
        credit = (outlet['Credit'] as int?) ?? 0;
      });
    }
  }

  String getGreeting() {
    final hour = DateTime
        .now()
        .hour;
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
  Future<void> _handleOutletSelection(BuildContext context) async {
    final outletJson = await _storage.read(key: 'outlets');

    if (outletJson == null) return;

    final List<dynamic> decoded = jsonDecode(outletJson);

    if (decoded.isEmpty) return;

    Map<String, dynamic>? selectedOutlet;


    selectedOutlet = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: Colors.white.withOpacity(0.95),
          child: Container(
            padding: const EdgeInsets.all(24),
            constraints: const BoxConstraints(maxHeight: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.store_mall_directory, size: 48, color: Colors.pink),
                const SizedBox(height: 12),
                const Text(
                  "Select an Outlet",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: decoded.map((outlet) {
                        final map = outlet as Map<String, dynamic>;
                        final name = map['Outlet']?['Name'] ?? 'Unnamed';
                        final address = map['Outlet']?['Address'] ?? '';
                        final credit = map['Credit']?.toString() ?? '0';

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                          leading: const Icon(Icons.store, color: Colors.teal),
                          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(address),
                          trailing: Text(
                            'RM $credit',
                            style: const TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onTap: () => {
                            Navigator.pop(context, map),

                          },
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );


      if (selectedOutlet == null) return;

    // ✅ Save selected outlet in storage
    await _storage.write(
      key: 'selected_outlet',
      value: jsonEncode(selectedOutlet),
    );
    _loadUserAndOutletInfo();
    // ✅ Notify parent
    widget.onOutletChanged?.call();

    setState(() {
      // trigger rebuild
    });
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
                    onTap: () async {
                      await _handleOutletSelection(context);
                    },
                    borderRadius: BorderRadius.circular(30),
                    child: Row(
                      children: [
                      CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.orange[700],
                      child: Text(
                        (fullName?.isNotEmpty == true ? fullName![0].toUpperCase() : '?'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
                            Text(
                              fullName ?? '',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.black,
                              ),
                            ),
                            if (outletName != null && outletName!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 0),
                                child: Text(
                                 'Outlet: ' + outletName!,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.black54,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      // ScaffoldMessenger.of(context).showSnackBar(
                      //   const SnackBar(content: Text('Wallet tapped')),
                      // );
                    },
                    borderRadius: BorderRadius.circular(30),
                    child: Row(
                      children: [
                        Icon(Icons.account_balance_wallet,
                            color: Colors.orange[700]),
                        const SizedBox(width: 6),
                        Text(
                          'Token : ${credit}',
                          style: TextStyle(
                            fontSize: 16,
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
        child: widget.body,
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
          currentIndex: widget.selectedIndex,

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
