import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BluetoothManager {
  static final BluetoothManager _instance = BluetoothManager._internal();

  factory BluetoothManager() => _instance;

  BluetoothManager._internal();

  BluetoothDevice? connectedDevice;

  bool get isConnected => connectedDevice != null;
}
