import 'package:tqrconnectv1/models/outlet_device.dart';
import 'dart:convert';

class Outlet {
  final int id;
  final String name;
  final List<OutletDevice> outletDevices;

  Outlet({
    required this.id,
    required this.name,
    required this.outletDevices,
  });

  factory Outlet.fromJson(Map<String, dynamic> json) {
    return Outlet(
      id: json['Id'],
      name: json['Name'],
      outletDevices: (json['Devices'] as List<dynamic>? ?? [])
          .map((deviceJson) => OutletDevice.fromJson(deviceJson))
          .toList(),
    );
  }

  static List<Outlet> listFromJson(List<dynamic> jsonList) {
    return jsonList
        .map((item) => Outlet.fromJson(item['Outlet'] ?? {}))
        .toList();
  }

  factory Outlet.empty() {
    return Outlet(
      id: 0,
      name: '',

      outletDevices: [],
      // ... any other required fields
    );
  }
}
