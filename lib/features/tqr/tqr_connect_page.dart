import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'package:tqrconnectv1/bluetooth_manager.dart'; // Replace with actual path
import '../../bluetooth/bluetooth_command.dart';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../models/outlet_device.dart';
import '../../models/outlet.dart';
import 'package:dio/dio.dart';
import 'dart:math';
import 'package:go_router/go_router.dart';

final GlobalKey<_TqrConnectPageState> tqrConnectPageKey = GlobalKey<_TqrConnectPageState>();

class TqrConnectPage extends StatefulWidget {
  final Outlet selectedOutlet;
  final VoidCallback? onCreditChanged; // ✅ add this

  const TqrConnectPage({super.key, required this.selectedOutlet, this.onCreditChanged});

  @override
  State<TqrConnectPage> createState() => _TqrConnectPageState();
}


class _TqrConnectPageState extends State<TqrConnectPage> {
  bool _isScanning = false;
  BluetoothDevice? _tqrDevice;
  bool _hasScanned = false;
  List<ScanResult> _scanResults = [];
  bool _isConnecting = false;
  bool _pollingPaused  = false;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  String? token = '';
  late Outlet _selectedOutlet;
  late List<OutletDevice> _devices;
  int _userCredit = 0;
  final dio = Dio();
  // Devices grouped by ID and their polling result (e.g., utd)
  Map<int, Map<String, String>> _presentMachines = {};
  Map<int, int> _pollingFailures = {};
  List<String> _targetMacAddresses = [];

  @override
  void initState() {
    super.initState();
    _loadSelectedOutletDevices().then((_) {
      loadtoken();

      final controllers = _devices.where((d) =>
      d.deviceType == 'Controller' &&
          d.macAddress != null &&
          d.macAddress!.isNotEmpty
      ).toList();

      _targetMacAddresses = controllers.map((d) => d.macAddress!.toUpperCase().replaceAll('-', ':')).toList();
      print("🎯 Target MAC Addresses: $_targetMacAddresses");

      final existingDevice = BluetoothManager().connectedDevice;
      if (existingDevice != null) {
        existingDevice.connectionState.listen((state) {
          if (state == BluetoothConnectionState.connected) {
            setState(() {
              _tqrDevice = existingDevice;
              _hasScanned = true;
            });
            _startContinuousPolling();
          } else {
            BluetoothManager().connectedDevice = null;
            setState(() {
              _tqrDevice = null;
            });
          }
        });
      }
    });
  }

  Future<void> loadtoken() async {
    await _loadSelectedOutletDevices();

    token = await _storage.read(key: 'auth_token');
    print("✅ Token loaded: $token");

  }

  void reloadOutletAndDevices() {
    print("🔁 reloadOutletAndDevices() triggered");
    _loadSelectedOutletDevices();
  }

  void resetForNewOutlet() {
    print("🔄 Resetting TQR Connect Page for new outlet...");

    // Stop all background activities
    _stopPolling();

    // Disconnect if a device is connected
    final device = BluetoothManager().connectedDevice;
    if (device != null) {
      device.disconnect();
      BluetoothManager().connectedDevice = null;
    }

    // Reset the state variables to their initial values
    setState(() {
      _isScanning = false;
      _tqrDevice = null;
      _hasScanned = false;
      _scanResults = [];
      _isConnecting = false;
      _pollingPaused = false;
      _presentMachines = {};
      _targetMacAddresses = [];
    });

    // Load the devices for the newly selected outlet
    _loadSelectedOutletDevices();
  }

  Future<void> _logTransaction({
    required String transactionId,
    required String deviceCode,
    required double amount,
    required String status,
    required String type,
    String? error,
  }) async {
    try {
      print('Transaction logged: $transactionId $deviceCode $amount $status $type $token');

      final response = await dio.post(
        'https://192.168.0.203/api/mobile/transaction/create',
        data: {
          'transactionid': transactionId,
          'devicecode': deviceCode,
          'amount': amount.toInt(),
          'status': status,
          'type': type,
          'errordescription': error ?? ''
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
          },
        ),
      );

      if(status == "Success"){
        widget.onCreditChanged?.call();
      }
      print('✅ Transaction logged: $response');
    } catch (e) {
      print('❌ Failed to log transaction: $e');
    }
  }


  Future<void> _loadSelectedOutletDevices() async {
    final selectedJson = await _storage.read(key: 'selected_outlet');

    if (selectedJson == null) return;

    final selected = jsonDecode(selectedJson);
    final outletMap = selected['Outlet'];

    final outlet = Outlet.fromJson(outletMap);

    setState(() {
      _selectedOutlet = outlet;
      _devices = outlet.outletDevices;
      _userCredit = selected['Credit'] as int? ?? 0;

      // 🔁 Update target MACs based on controllers
      _targetMacAddresses = _devices
          .where((d) =>
      d.deviceType == 'Controller' &&
          d.macAddress != null &&
          d.macAddress!.isNotEmpty)
          .map((d) => d.macAddress!.toUpperCase().replaceAll('-', ':')) // 👈 Normalize to colon
          .toList();
    });

    print("✅ Loaded ${_devices.length} devices from selected outlet.");
    print('🎯 Target MAC Addresses: $_targetMacAddresses');
  }

  Future<bool> _isTokenExpired() async {
    final expiryDateString = await _storage.read(key: 'token_expiry');
    print("🔒 Checking token expiration. Stored expiry string: $expiryDateString");

    if (expiryDateString == null) {
      print("⚠️ No expiry date found in storage. Assuming token is expired.");
      return true; // Assume expired if no date is stored
    }

    try {
      final expiryDate = DateTime.parse(expiryDateString).toUtc();
      final now = DateTime.now().toUtc();

      print("   - Expiry date (UTC): ${expiryDate.toIso8601String()}");
      print("   - Current time (UTC):     ${now.toIso8601String()}");

      final isExpired = now.isAfter(expiryDate);
      print("   - Is token expired? $isExpired");

      return isExpired;
    } catch (e) {
      print("❌ Error parsing expiry date: $e. Assuming token is expired.");
      return true;
    }
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
      _userCredit = newCredit;
    });
  }


  Future<void> _handleOutletSelection(BuildContext context) async {
    final outletJson = await _storage.read(key: 'outlets');

    if (outletJson == null) return;

    final List<dynamic> decoded = jsonDecode(outletJson);

    if (decoded.isEmpty) return;

    Map<String, dynamic>? selectedOutlet;

    if (decoded.length == 1) {
      selectedOutlet = decoded[0] as Map<String, dynamic>;
    } else {
      selectedOutlet = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (context) => SimpleDialog(
          title: const Text("Select an Outlet"),
          children: decoded.map((outlet) {
            final map = outlet as Map<String, dynamic>;
            final outletName = map['Outlet']?['Name'] ?? 'Unnamed';
            return SimpleDialogOption(
              onPressed: () => Navigator.pop(context, map),
              child: Text(outletName),
            );
          }).toList(),
        ),
      );

      if (selectedOutlet == null) return;
    }

    // ✅ Save selected outlet in storage
    await _storage.write(
      key: 'selected_outlet',
      value: jsonEncode(selectedOutlet),
    );

    setState(() {
      // trigger rebuild
    });
  }


  Future<bool> requestBluetoothPermissions() async {
    // For Android 12+
    if (await Permission.bluetoothScan
        .request()
        .isDenied ||
        await Permission.bluetoothConnect
            .request()
            .isDenied ||
        await Permission.locationWhenInUse
            .request()
            .isDenied) {
      return false;
    }

    // Optional for Android < 12
    if (await Permission.location
        .request()
        .isDenied) {
      return false;
    }

    return true;
  }

  Timer? _pollingTimer;

  bool _isPolling = false;

  void _startContinuousPolling() {
    if (_isPolling) {
      print("⚠️ Polling already running — exiting early");
      return;
    }

    final device = _tqrDevice;
    final notifyChar = BluetoothManager().notifyChar;
    final writeChar = BluetoothManager().writeChar;

    if (device == null || notifyChar == null || writeChar == null) {
      print("❌ Device or characteristics not ready for polling.");
      return;
    }

    _isPolling = true;
    print("📡 Starting continuous polling...");

    Timer.run(() async {
      while (mounted && _isPolling && _tqrDevice != null) {
        if (_pollingPaused) {
          print("⏸ Polling paused...");
          await Future.delayed(const Duration(milliseconds: 500));
          continue;
        }

        final injectors = _devices.where((d) => d.deviceType == 'PulseInjector').toList();

        for (int i = 0; i < injectors.length; i++) {
          if (!mounted || !_isPolling || _pollingPaused) break;

          final injector = injectors[i];
          final id = injector.sequence != 0 ? injector.sequence : (i + 1);
          final injectormac = injector.macAddress;
          print("➡️ Polling Machine ID: $id $injectormac ");

          try {
            final result = await BluetoothUtils.sendPollingCommand(
              device: _tqrDevice!,
              id: id,
              password: "000000",
              macaddress: injector.macAddress ?? "",
              mode: injector.mode ?? "",
              pulseinterval: injector.pulseInterval?.toString() ?? "",
              pulsespace: injector.pulseSpace?.toString() ?? "",
              notifyChar: notifyChar,
              writeChar: writeChar,
            );

            if (result != null) {
              print("✅ Polling success for ID $id: utd=${result["utd"]} macaddress=${result["macaddress"]}");
              setState(() {
                final freshInjector = _devices.firstWhere(
                        (d) => d.deviceType == 'PulseInjector' && d.macAddress == result["macaddress"],
                    orElse: () => injector
                );

                _presentMachines[id] = {
                  "utd": result["utd"],
                  "machineName": freshInjector.machineName ?? 'Machine $id',
                  "machineCode": freshInjector.machineCode ?? 'Code $id',
                  "macAddress": freshInjector.macAddress ?? 'FF-FF-FF-FF-FF-FF',
                  "deviceCode" : freshInjector.deviceCode
                };
                _pollingFailures[id] = 0; // Reset on success
              });
            } else {
              print("❌ Polling failed for ID $id");
              setState(() {
                _pollingFailures[id] = (_pollingFailures[id] ?? 0) + 1;
                if (_pollingFailures[id]! >= 3) {
                  _presentMachines.remove(id);
                  print("Machine ID $id removed after 3 failed attempts.");
                }
              });
            }
          } catch (e) {
            print("❌ Polling error for ID $id: $e");
            setState(() {
              _pollingFailures[id] = (_pollingFailures[id] ?? 0) + 1;
              if (_pollingFailures[id]! >= 3) {
                _presentMachines.remove(id);
                print("Machine ID $id removed after 3 failed attempts due to error.");
              }
            });
          }

          await Future.delayed(const Duration(milliseconds: 100));
        }

        print("🕓 Polling loop complete — restarting after short delay");
        await Future.delayed(const Duration(seconds: 0));
      }

      _isPolling = false;
      print("🛑 Polling loop exited");
    });
  }

  void _stopPolling() {
    print("🛑 Stopping polling loop manually");
    _isPolling = false;
  }


  void _startScan() async {
    final hasPermission = await requestBluetoothPermissions();
    if (!hasPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Bluetooth permissions are required")),
      );
      return;
    }

    setState(() {
      _isScanning = true;
      _tqrDevice = null;
      _hasScanned = true;
      _scanResults = []; // clear list
    });

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));

      final subscription = FlutterBluePlus.scanResults.listen((results) {
        for (var result in results) {
          final device = result.device;
          final mac = device.remoteId.str.toUpperCase();
          final name = device.platformName;
          final rssi = result.rssi;

          // ✅ Print all scanned devices
          print('result: ${result}' );
          print('mac: ${_targetMacAddresses}' );

          if (_targetMacAddresses.contains(mac)) {
            if (!_scanResults.any((r) => r.device.remoteId == device.remoteId)) {
              _scanResults.add(result);
              print("✅ Added new device: $mac");
            }
          }

        }
      });

      // Wait for timeout
      await Future.delayed(const Duration(seconds: 2));
      await subscription.cancel();
      await FlutterBluePlus.stopScan();
    } catch (e) {
      print("❌ Error during scan: $e");
      await FlutterBluePlus.stopScan();
    }

    setState(() {
      _isScanning = false;
    });
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    setState(() {
      _isConnecting = true;
    });

    try {
      await device.connect(autoConnect: false);
      print("✅ Connected to ${device.remoteId.str}");

      // 👂 Listen for disconnection
      device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          print("🔌 Device disconnected unexpectedly.");
          _stopPolling();
          BluetoothManager().connectedDevice = null;
          if (mounted) {
            setState(() {
              _tqrDevice = null;
              _presentMachines.clear(); // Clear machine list
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Device has disconnected."),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      });

      // Save connected device
      BluetoothManager().connectedDevice = device;
      setState(() {
        _tqrDevice = device;
      });

      // Discover services
      List<BluetoothService> services = await device.discoverServices();
      BluetoothService? targetService;
      BluetoothCharacteristic? notifyChar;
      BluetoothCharacteristic? writeChar;

      for (var service in services) {
        print("🔧 Service: ${service.uuid.str}");

        if (service.uuid.str.toLowerCase().contains("abf0")) {
          targetService = service;

          for (var char in service.characteristics) {
            print("  ↳ Characteristic: ${char.uuid.str}");
            print("     Properties: read=${char.properties.read},"
                " write=${char.properties.write},"
                " writeWithoutResponse=${char.properties.writeWithoutResponse},"
                " notify=${char.properties.notify}");

            if (char.uuid.str.toLowerCase().contains("abf2")) {
              notifyChar = char;
            } else if (char.uuid.str.toLowerCase().contains("abf1")) {
              writeChar = char;
            }
          }
        }
      }

      // Ensure both characteristics found
      if (notifyChar == null || writeChar == null) {
        print("❌ Required characteristics not found");
        await device.disconnect();
        return;
      }

      // 🔔 Enable notify ONCE after connect
      await notifyChar.setNotifyValue(true);
      print("✅ Notification enabled on abf2");

      // Store globally or pass to your utility
      BluetoothManager().notifyChar = notifyChar;
      BluetoothManager().writeChar = writeChar;

      // ✅ Start polling after everything is ready
      if (_isPolling) {
        print("⛔ Restarting polling: stopping previous loop");
        _isPolling = false;
        await Future.delayed(const Duration(milliseconds: 100)); // short gap
      }
      _startContinuousPolling();

    } catch (e) {
      print("❌ Connection failed: $e");
    } finally {
      setState(() {
        _isConnecting = false;
      });
    }
  }

  Widget _buildSignalIcon(int rssi) {
    Color color;

    if (rssi >= -50) {
      color = Colors.green;
    } else if (rssi >= -60) {
      color = Colors.lightGreen;
    } else if (rssi >= -70) {
      color = Colors.orange;
    } else {
      color = Colors.red;
    }

    return Icon(Icons.network_wifi, color: color);
  }

  void _showInjectDialog(BuildContext context, int machineId, String utd, String macAddress, String machineName, String machineCode) async {
    if (await _isTokenExpired()) {
      print("🔒 Token is expired. Redirecting to login.");
      if (mounted) {
        await _showSessionExpiredDialog(context);
      }
      return;
    }
     await refreshCredit();
    final parentContext = context;
    double injectValue = 1;

    // 👇 Get the current controller MAC
    final controllerMac = _tqrDevice?.remoteId.str.toUpperCase() ?? "";

    // 👇 Find the corresponding pulse injector
    final injector = _devices.firstWhere(
          (d) =>
      d.deviceType == 'PulseInjector' &&
          d.macAddress?.toUpperCase() == macAddress,
      orElse: () => OutletDevice(
        outletId: _selectedOutlet.id,
        macAddress: '',
        deviceType: '',
        deviceCode: '',
        machineName: '',
        machineCode: '',
        sequence: 0,
      ),
    );

    if (injector.macAddress == null || injector.macAddress!.isEmpty) {
      print("❌ No matching pulse injector found for ID $machineId and controller $controllerMac");
      return;
    }

    showDialog(
      context: parentContext,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return StatefulBuilder(
          builder: (context, setInjectState) {
            return AlertDialog(
              title: Center(child: Text("Inject Machine $machineCode")),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Select amount to inject:"),
                  const SizedBox(height: 10),
                  Slider(
                    value: injectValue,
                    min: 1,
                    max: 10,
                    divisions: 9,
                    label: injectValue.round().toString(),
                    onChanged: (value) {
                      setInjectState(() => injectValue = value);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  child: const Text("Cancel"),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
                ElevatedButton(
                  child: const Text("Confirm"),
                  onPressed: () async {
                    if (injectValue > _userCredit) {
                      Navigator.of(dialogContext).pop(); // Close the inject dialog
                      await _showInsufficientCreditDialog(parentContext);
                      return;
                    }

                    setState(() {
                      _pollingPaused = true;
                    });
                    final valueToInject = injectValue;
                    Navigator.of(dialogContext).pop();
                    await Future.delayed(const Duration(milliseconds: 100));

                    if (!mounted) return;

                    final loadingContext = Navigator.of(parentContext).overlay!.context;

                    showDialog(
                      context: loadingContext,
                      barrierDismissible: false,
                      builder: (_) => const Center(child: CircularProgressIndicator()),
                    );

                    try {
                      if (_tqrDevice == null) throw Exception("No device connected");

                      final result = await BluetoothUtils.sendInjectCommand(
                        device: _tqrDevice!,
                        id: machineId,
                        channel: 1,
                        counter: valueToInject.toInt(),
                        password: "000000",
                        utd: utd.toString(),
                        macaddress: injector.macAddress ?? "",
                        mode: injector.mode ?? "",
                        pulseinterval: injector.pulseInterval?.toString() ?? "",
                        pulsespace: injector.pulseSpace?.toString() ?? "",
                        notifyChar: BluetoothManager().notifyChar!,  // 👈 make sure it's set after connect
                        writeChar: BluetoothManager().writeChar!,    // 👈 same here
                      );

                      setState(() {
                        _pollingPaused = false;
                      });

                      if (!mounted) return;
                      Navigator.of(loadingContext).pop();

                      if (result.result && result.utd != null) {
                        setState(() {
                          _presentMachines[machineId] ??= {};
                          _presentMachines[machineId]!["utd"] = result.utd.toString();
                          _userCredit -= valueToInject.toInt(); // 👈 Decrement local credit
                        });

                        // Notify parent to refresh credit from server
                        widget.onCreditChanged?.call();

                        final random = Random().nextInt(100000); // Random 5-digit number
                        final now = DateTime.now().millisecondsSinceEpoch;

                        final transactionId = '$now$random';

                        await _logTransaction(
                          transactionId: transactionId,
                          deviceCode: injector.deviceCode,
                          amount: valueToInject,
                          status: 'Success',
                          type: 'Inject',
                        );



                        await _showResultDialog(
                          parentContext,
                          success: true,
                          message: "Injected into Machine $machineCode \nutd: ${result.utd}",
                        );
                      } else {
                        final random = Random().nextInt(100000); // Random 5-digit number
                        final now = DateTime.now().millisecondsSinceEpoch;

                        final transactionId = '$now$random';

                        await _logTransaction(
                          transactionId: transactionId,
                          deviceCode: injector.deviceCode,
                          amount: valueToInject,
                          status: 'Failed',
                          type: 'Inject',
                          error: 'Timeout'
                        );



                        await _showResultDialog(
                          parentContext,
                          success: false,
                          message: "Inject failed for Machine $machineCode",
                        );
                      }
                    } catch (e) {
                      final random = Random().nextInt(100000); // Random 5-digit number
                      final now = DateTime.now().millisecondsSinceEpoch;
                      print("❌ Inject Error: $e");
                      final transactionId = '$now$random';

                      await _logTransaction(
                        transactionId: transactionId,
                        deviceCode: injector.deviceCode,
                        amount: valueToInject,
                        status: 'Failed',
                        type: 'Inject', error: '$e'
                      );



                      if (mounted) {
                        Navigator.of(loadingContext).pop();
                        await _showResultDialog(
                          parentContext,
                          success: false,
                          message: "Inject failed for Machine $machineCode\nError: $e",
                        );
                      }
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showResultDialog(
      BuildContext context, {
        required bool success,
        required String message,
      }) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Material(
          color: Colors.transparent,
          child: AnimatedScale(
            scale: 1.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            child: Container(
              width: 280,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    success ? Icons.check_circle_rounded : Icons.error_rounded,
                    color: success ? Colors.green : Colors.red,
                    size: 72,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    success ? "Success" : "Failed",
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await Future.delayed(const Duration(seconds: 2));

    if (context.mounted) Navigator.of(context).pop(); // Close the dialog
  }

  Future<void> _showSessionExpiredDialog(BuildContext context) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Session Expired"),
        content: const Text("Your session has expired. Please log in again to continue."),
        actions: [
          TextButton(
            child: const Text("OK"),
            onPressed: () {
              Navigator.of(dialogContext).pop(); // Close the dialog
              context.go('/login');
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showInsufficientCreditDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Insufficient Credit"),
        content: const Text("You do not have enough credit to perform this action."),
        actions: [
          TextButton(
            child: const Text("OK"),
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_hasScanned)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'TQR is not connected!',
                    style: Theme
                        .of(context)
                        .textTheme
                        .titleLarge,
                  ),
                  const SizedBox(height: 16),
                  _isScanning
                      ? const CircularProgressIndicator()
                      : ElevatedButton(
                    onPressed: _startScan,
                    child: const Text('Connect Now'),
                  ),
                ],
              ),
            ),
          ),

        if (_hasScanned && _tqrDevice == null) ...[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.search),
                    label: const Text('Search Again'),
                    onPressed: _isScanning ? null : _startScan,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                Expanded(
                  child: _isScanning
                      ? const Center(child: CircularProgressIndicator())
                      : _scanResults.isNotEmpty
                      ? ListView(
                    padding: const EdgeInsets.all(8),
                    children: _scanResults.map((result) {
                      final device = result.device;
                      final name = device.platformName.isNotEmpty
                          ? device.platformName
                          : '(Unknown)';
                      final mac = device.remoteId.str;
                      final rssi = result.rssi;

                      return Card(
                        elevation: 3,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              const Icon(Icons.bluetooth, size: 28),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name,
                                        style: Theme.of(context).textTheme.titleMedium),
                                    Text('$mac'),
                                  ],
                                ),
                              ),
                              ElevatedButton(
                                onPressed: _isConnecting ? null : () => _connectToDevice(device),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.primaryColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: _isConnecting
                                    ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                                    : const Text("Connect"),
                              ),

                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  )

                      : Center(
                    child: Text(
                      'No devices found.\nPlease try again.',
                      textAlign: TextAlign.center,
                      style: Theme
                          .of(context)
                          .textTheme
                          .bodyLarge,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        if (_tqrDevice != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 5, 10, 0), // 👈 No top padding
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Controller Header (Styled)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 16, horizontal: 16),
                        decoration: BoxDecoration(
                          color: theme.primaryColor.withOpacity(0.1),
                          borderRadius: const BorderRadius.vertical(top: Radius
                              .circular(12)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [

                            const SizedBox(width: 8),
                            Text(
                              "Controller",
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,

                              ),
                            ),
                          ],
                        ),
                      ),

                      // Controller Details
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.developer_board, size: 36),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment
                                        .start,
                                    children: [
                                      Text(
                                        _tqrDevice!.platformName.isNotEmpty
                                            ? _tqrDevice!.platformName
                                            : '(Unknown Device)',
                                        style: theme.textTheme.titleMedium,
                                      ),
                                      Text(_tqrDevice!.remoteId.str),
                                    ],
                                  ),
                                ),
                                if (_scanResults.any((r) =>
                                r.device.remoteId == _tqrDevice!.remoteId)) ...[
                                  const SizedBox(width: 8),
                                  _buildSignalIcon(
                                    _scanResults
                                        .firstWhere(
                                          (r) =>
                                      r.device.remoteId == _tqrDevice!.remoteId,
                                    )
                                        .rssi,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.cancel),
                                label: const Text('Disconnect'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 14),
                                ),
                                onPressed: () async {
                                  try {
                                    await _tqrDevice?.disconnect();
                                    setState(() {
                                      _tqrDevice = null;
                                    });
                                    print("🔌 Disconnected.");
                                  } catch (e) {
                                    print("❌ Error disconnecting: $e");
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              ],
            ),
          ),
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                    decoration: BoxDecoration(
                      color: theme.primaryColor.withOpacity(0.1),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.local_laundry_service, size: 24),
                        const SizedBox(width: 8),
                        Text(
                          "Available Machines",
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Scrollable machine list with fixed height
                  SizedBox(
                    height: 332, // Adjust this height as needed
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child:ListView.separated(
                        itemCount: _devices.where((d) => d.deviceType == 'PulseInjector').length,
                        separatorBuilder: (_, __) => const Divider(height: 20),
                        itemBuilder: (context, index) {
                          final injectors = _devices.where((d) => d.deviceType == 'PulseInjector').toList();
                          injectors.sort((a, b) {
                            final aIsPresent = _presentMachines.containsKey(a.sequence);
                            final bIsPresent = _presentMachines.containsKey(b.sequence);
                            if (aIsPresent && !bIsPresent) return -1;
                            if (!aIsPresent && bIsPresent) return 1;
                            return a.sequence.compareTo(b.sequence);
                          });

                          final injector = injectors[index];
                          final id = injector.sequence;
                          final isPresent = _presentMachines.containsKey(id);
                          final utd = isPresent ? _presentMachines[id]!['utd']! : "-";
                          final machineName = injector.machineName ?? 'Machine $id';
                          final machineCode = injector.machineCode ?? 'Code $id';
                          final macAddress = injector.macAddress ?? 'FF-FF-FF-FF-FF-FF';

                          return Row(
                            children: [
                              Icon(Icons.local_laundry_service_outlined, size: 28, color: isPresent ? theme.primaryColor : Colors.grey),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      machineName,
                                      style: theme.textTheme.bodyLarge?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: isPresent ? Colors.black : Colors.grey,
                                      ),
                                    ),
                                    Text("Code: $machineCode", style: TextStyle(color: isPresent ? Colors.black54 : Colors.grey)),
                                    Text("UTD: $utd", style: TextStyle(color: isPresent ? Colors.black54 : Colors.grey)),
                                  ],
                                ),
                              ),
                              if (isPresent)
                                ElevatedButton.icon(
                                  onPressed: () => _showInjectDialog(context, id, utd, macAddress, machineName, machineCode),
                                  icon: const Icon(Icons.flash_on, size: 18),
                                  label: const Text("Inject"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: theme.colorScheme.secondary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),



        ],

      ],
    );
  }
}
