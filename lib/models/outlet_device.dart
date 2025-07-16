class OutletDevice {

  final int? outletId;
  final String deviceCode;
  final String? machineName;
  final String? machineCode;
  final int sequence;
  final String? status;
  final String? mode;
  final int? pulseSpace;
  final int? pulseInterval;
  final String? deviceType;
  final String? macAddress;

  // ✅ Constructor
  OutletDevice({

    this.outletId,
    required this.deviceCode,
    this.machineName,
    this.machineCode,
    required this.sequence,
    this.status,
    this.mode,
    this.pulseInterval,
    this.pulseSpace,
    this.deviceType,
    this.macAddress
  });

  // ✅ fromJson factory
  factory OutletDevice.fromJson(Map<String, dynamic> json) {
    return OutletDevice(

      outletId: json['OutletId'],
      deviceCode: json['DeviceCode'],
      machineName: json['MachineName'],
      machineCode: json['MachineCode'],
      sequence: json['Sequence'],
      status: json['Status'],

      macAddress: json['MacAddress'],
      deviceType: json['DeviceType'],
      mode: json['Mode'],
      pulseInterval: json['PulseInterval'],
      pulseSpace: json['PulseSpace'],
    );
  }
}
