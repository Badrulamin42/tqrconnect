import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'package:tqrconnectv1/bluetooth_manager.dart'; // Replace with actual path
import '../../bluetooth/bluetooth_command.dart';

class TqrConnectPage extends StatefulWidget {
  @override
  State<TqrConnectPage> createState() => _TqrConnectPageState();
}



class _TqrConnectPageState extends State<TqrConnectPage> {
  bool _isScanning = false;
  BluetoothDevice? _tqrDevice;
  final String targetMacAddress = "74:4D:BD:7C:82:2A";
  bool _hasScanned = false;
  List<ScanResult> _scanResults = [];
  bool _isConnecting = false;
  bool _pollingPaused  = false;

  @override
  void initState() {
    super.initState();

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
  Map<int, Map<String, String>> _presentMachines = {};

  void _startContinuousPolling() {

    print("📡 Starting continuous polling...");

    // ✅ Define and call the async function properly
    () async {
      while (mounted && _tqrDevice != null) {
        print("🔄 New polling loop started...");

        for (int id = 1; id <= 16; id++) {
          if (_tqrDevice == null) {
            print("⚠️ Device became null. Stopping polling.");
            break;
          }
          while (_pollingPaused) {
            await Future.delayed(Duration(milliseconds: 500));
          }
          print("➡️ Polling Machine ID: $id");

          final result = await BluetoothUtils.sendPollingCommand(
            device: _tqrDevice!,
            id: id,
            password: "000000",
          );

          if (!mounted) {
            print("🛑 Widget no longer mounted. Stopping polling.");
            return;
          }

          if (result != null) {
            print("✅ Polling success for ID $id: utd1=${result["utd1"]}, utd2=${result["utd2"]}");
          } else {
            print("❌ Polling failed for ID $id");
          }

          setState(() {
            if (result != null) {
              _presentMachines[id] = {
                "utd1": result["utd1"],
                "utd2": result["utd2"],
              };
            } else {
              _presentMachines.remove(id);
            }
          });

          await Future.delayed(const Duration(milliseconds: 50));
        }
      }

    }(); // 👈 This is the missing part — CALL the function
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

          final mac1 = result.device.remoteId.str.toUpperCase();
          if (mac1 == targetMacAddress.toUpperCase() &&
              !_scanResults.any((r) =>
              r.device.remoteId == result.device.remoteId)) {
            _scanResults.add(result);

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

      // Store globally
      BluetoothManager().connectedDevice = device;

      setState(() {
        _tqrDevice = device;
      });

      // 🔍 Discover and print all services/characteristics
      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        print("🔧 Service: ${service.uuid.str}");
        for (var characteristic in service.characteristics) {
          print("  ↳ Characteristic: ${characteristic.uuid.str}");
          print("     Properties:"
              " read=${characteristic.properties.read},"
              " write=${characteristic.properties.write},"
              " writeWithoutResponse=${characteristic.properties.writeWithoutResponse},"
              " notify=${characteristic.properties.notify}");
        }
      }


      _startContinuousPolling(); // start polling after discovery
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

  void _showInjectDialog(BuildContext context, int machineId) {
    final parentContext = context;
    double injectValue = 1;

    showDialog(
      context: parentContext,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return StatefulBuilder(
          builder: (context, setInjectState) {
            return AlertDialog(
              title: Center(child: Text("Inject Machine $machineId")),
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
                    setState(() {
                      _pollingPaused = true;
                    });
                    final valueToInject = injectValue;
                    Navigator.of(dialogContext).pop();
                    await Future.delayed(const Duration(milliseconds: 100));

                    if (!mounted) return;

                    // ✅ Use correct context for loading dialog
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
                      );

                      setState(() {
                        _pollingPaused = false;
                      });

                      if (!mounted) return;
                      Navigator.of(loadingContext).pop(); // ✅ close spinner

                      if (result.result && result.utd1 != null) {
                        setState(() {
                          _presentMachines[machineId] ??= {};
                          _presentMachines[machineId]!["utd1"] = result.utd1.toString();
                        });

                        await _showResultDialog(
                          parentContext,
                          success: true,
                          message: "Injected into Machine $machineId\nUTD1: ${result.utd1}",
                        );
                      } else {
                        await _showResultDialog(
                          parentContext,
                          success: false,
                          message: "Inject failed for Machine $machineId",
                        );
                      }
                    } catch (e) {
                      print("❌ Inject Error: $e");
                      if (mounted) {
                        Navigator.of(loadingContext).pop(); // ✅ always close
                        await _showResultDialog(
                          parentContext,
                          success: false,
                          message: "Inject failed for Machine $machineId\nError: $e",
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
                        itemCount: _presentMachines.length,
                        separatorBuilder: (_, __) => const Divider(height: 20),
                        itemBuilder: (context, index) {
                          final id = _presentMachines.keys.elementAt(index);
                          final utd1 = _presentMachines[id]?['utd1'] ?? "-";
                          final utd2 = _presentMachines[id]?['utd2'] ?? "-";
                          final machineName = "Machine $id";

                          return Row(
                            children: [
                              const Icon(Icons.local_laundry_service_outlined, size: 28),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      machineName,
                                      style: theme.textTheme.bodyLarge?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text("UTD1: $utd1  |  UTD2: $utd2"),
                                  ],
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: () => _showInjectDialog(context, id),
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
