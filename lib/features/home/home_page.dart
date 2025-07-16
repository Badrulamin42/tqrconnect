import 'package:flutter/material.dart';
import '../../widgets/main_scaffold.dart';
import '../tqr/tqr_connect_page.dart'; // import
import '../../models/outlet.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

final GlobalKey<MainScaffoldState> mainScaffoldKey = GlobalKey<MainScaffoldState>();

class HomePage extends StatefulWidget {
  final List<Outlet>? outlets;
  final VoidCallback? onCreditChanged;

  const HomePage({super.key, this.outlets, this.onCreditChanged});

  @override
  State<HomePage> createState() => _HomePageState();
}


class _HomePageState extends State<HomePage> {
  final _storage = const FlutterSecureStorage();
  bool _loading = false;
  List<Outlet>? _outlets;
  Outlet? _selectedOutlet;
  @override
  void initState() {
    super.initState();
    _loadOutletFromStorage();
    _outlets = widget.outlets;

    if (_outlets == null || _outlets!.isEmpty) {
      _handleOutletSelection(context);
    }
  }

  void _reloadSelectedOutlet() async {
    final outletJson = await _storage.read(key: 'selected_outlet');
    if (outletJson != null) {
      final selected = jsonDecode(outletJson);
      final outlet = Outlet.fromJson(selected['Outlet']);
      setState(() {
        _selectedOutlet = outlet;
      });
    }
  }

  Future<void> _loadOutletFromStorage() async {

    final outletJson = await _storage.read(key: 'selected_outlet');
    final allOutletsJson = await _storage.read(key: 'outlets');

    if (outletJson == null || allOutletsJson == null) return;

    final decoded = jsonDecode(allOutletsJson) as List<dynamic>;
    final selected = jsonDecode(outletJson);

    final outlet = Outlet.fromJson(selected['Outlet']);
    final newOutletList = Outlet.listFromJson(decoded);

    setState(() {
      _outlets = newOutletList;
      _selectedOutlet = outlet;
      _loading = false;
    });
  }


  Future<void> _handleOutletSelection(BuildContext context) async {
    setState(() => _loading = true);

    final outletJson = await _storage.read(key: 'outlets');
    if (outletJson == null) {
      setState(() => _loading = false);
      return;
    }

    final List<dynamic> decoded = jsonDecode(outletJson);
    if (decoded.isEmpty) {
      setState(() => _loading = false);
      return;
    }

    // Try to load previously selected
    final selectedJson = await _storage.read(key: 'selected_outlet');
    Map<String, dynamic>? selected;

    if (selectedJson != null) {
      selected = jsonDecode(selectedJson);
    } else {
      // 🪄 Beautiful custom modal with blur + scroll
      selected = await showGeneralDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        barrierLabel: 'Outlet Selection',
        barrierColor: Colors.black.withOpacity(0.5), // semi-dark blur background
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, __, ___) {
          return Stack(
            fit: StackFit.expand,
            children: [
              // 🌄 Pattern background
              Container(
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('assets/images/pattern_bg.png'),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              // 🖤 Optional dark overlay
              Container(color: Colors.black.withOpacity(0.5)),

              // 🎯 Centered dialog
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      )
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
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
                        SizedBox(
                          height: 300,
                          child: SingleChildScrollView(
                            child: Column(
                              children: decoded.map((outlet) {
                                final map = outlet as Map<String, dynamic>;
                                final name = map['Outlet']?['Name'] ?? 'Unnamed';
                                final address = map['Outlet']?['Address'] ?? '';
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                  leading: const Icon(Icons.store, color: Colors.teal),
                                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  subtitle: Text(address),
                                  onTap: () => Navigator.pop(context, map),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },

      );

      if (selected != null) {
        await _storage.write(
          key: 'selected_outlet',
          value: jsonEncode(selected),
        );

        // 🔁 Rebuild with new selected outlet
        final outlet = Outlet.fromJson(selected['Outlet']);
        final newOutletList = Outlet.listFromJson(decoded);
        setState(() {
          _selectedOutlet = outlet;
          _outlets = newOutletList;
          _loading = false;
        });
        return; // prevent fallback load
      }

    }

    final newOutletList = Outlet.listFromJson(decoded);
    setState(() {
      _outlets = newOutletList;
      _loading = false;
    });
  }



  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_outlets == null || _outlets!.isEmpty) {
      return const Center(child: Text("No outlet selected."));
    }

    return MainScaffold(
      key: mainScaffoldKey,
      selectedIndex: 1,
      onOutletChanged: () {
        // 🔁 Trigger reload in TqrConnectPage
        tqrConnectPageKey.currentState?.resetForNewOutlet();
      },
      body: TqrConnectPage(
        key: tqrConnectPageKey,
        selectedOutlet: Outlet.empty(), // 🟡 Placeholder outlet — can be dummy
        onCreditChanged: () {
          mainScaffoldKey.currentState?.refreshCredit(); // 🔁 refresh credit after inject
        },
      ),
    );


  }
}


