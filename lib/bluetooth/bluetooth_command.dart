import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';


class InjectResult {
  final bool result;
  final int? utd;
  final int id;

  InjectResult({
    required this.result,
    required this.utd,
    required this.id,
  });
}

int? _extractutdFromPolling(List<dynamic>? responseList) {
  try {
    if (responseList == null || responseList.isEmpty) return null;

    final pollingData = responseList.firstWhere(
          (item) =>
      item is Map<String, dynamic> && item["commandcode"] == "polling",
      orElse: () => null,
    );

    if (pollingData == null || pollingData["data"] == null) return null;

    return int.tryParse(pollingData["data"]["utd"].toString());
  } catch (e) {
    print("❌ Error parsing utd: $e");
    return null;
  }
}


class BluetoothUtils {
  static final Guid _serviceUuid = Guid("0000abf0-0000-1000-8000-00805f9b34fb");
  static final Guid _writeCharUuid = Guid(
      "0000abf1-0000-1000-8000-00805f9b34fb");
  static final Guid _notifyCharUuid = Guid(
      "0000abf2-0000-1000-8000-00805f9b34fb");


  /// Sends a polling command to the device and waits for the response
  static Future<Map<String, dynamic>?> sendPollingCommand({
    required BluetoothDevice device,
    required int id,
    required String password,
    required String macaddress,
    required String mode,
    required String pulseinterval,
    required String pulsespace,
    required BluetoothCharacteristic notifyChar,
    required BluetoothCharacteristic writeChar,
  }) async {
    if (id < 1 || id > 16) throw ArgumentError('ID must be between 1 and 16');

    final unixTime = (DateTime
        .now()
        .millisecondsSinceEpoch ~/ 1000).toString();
    final dataPayload = {
      "commandcode": "polling",
      "data": {
        "unixtime": unixTime,
        "address": id.toString(),
        "macaddress":macaddress,
        "mode": mode,
        "pulseinterval": pulseinterval,
        "pulsespace": pulsespace,
        "inject": "0"
      },
    };

    final fullJson = _wrapWithSignature(device, password, [dataPayload]);

    try {
      final response = await BluetoothUtils.sendCommandAndListenProperly(
        device: device,
        fullJson: fullJson,
        notifyChar: notifyChar,
        writeChar: writeChar,
      );

      final parsed = jsonDecode(response);
      if (parsed is List && parsed.isNotEmpty) {
        final data = parsed[0]['data'];

        print('test1 : ${data}');
        if (data is Map && data['status'] == 'present') {
          return {
            "id": int.parse(data['address']),
            "utd": data['utd'],
            "macaddress":data['macaddress']

          };
        }
      }
    } catch (e) {
      print("❌ Polling error: $e");
    }

    return null;
  }

  static Future<InjectResult> sendInjectCommand({
    required BluetoothDevice device,
    required int id,
    required int channel,
    required int counter,
    required String password,
    required String utd,
    required String macaddress,
    required String mode,
    required String pulseinterval,
    required String pulsespace,
    required BluetoothCharacteristic notifyChar,
    required BluetoothCharacteristic writeChar,
  }) async {
    for (int i = 0; i < 3; i++) {
      try {
        await Future.delayed(const Duration(milliseconds: 500));
        // Step 1: Initial polling to get utd

        final initialutd = int.tryParse(utd ?? "");

        if (initialutd == null) {
          print("❌ Initial polling failed or utd not found.");
          return InjectResult(result: false, utd: null, id: id);
        }

        // Step 2: Inject command
        final unixTime = (DateTime
            .now()
            .millisecondsSinceEpoch ~/ 1000).toString();
        final dataPayload = {
          "commandcode": "polling",
          "data": {
            "address": id.toString(),
            "macaddress":macaddress,
            "unixtime": unixTime,
            "mode": mode,
            "pulseinterval": pulseinterval,
            "pulsespace": pulsespace,
            "inject": counter.toString()

          },
        };
        final fullJson = await _wrapWithSignature(
            device, password, [dataPayload]);

        final injectResponseString = await BluetoothUtils.sendCommandAndListenProperly(
          device: device,
          fullJson: fullJson,
          notifyChar: notifyChar,
          writeChar: writeChar,
        );

        await Future.delayed(const Duration(milliseconds: 1000));
        print("📥 Inject Response: $injectResponseString");

        final injectResponse = jsonDecode(injectResponseString);

        final data = injectResponse[0]['data'];
        print("❌ ${data}");
        int? afterutd = int.tryParse(data["utd"]?.toString() ?? '');


        if (afterutd == null) {
          print("❌ After polling failed or utd not found.");
          return InjectResult(result: false, utd: null, id: id);
        }

        // Step 4: Compare utd
        bool isSuccess = false;

        if (afterutd != null && afterutd > initialutd) {
          isSuccess = true;
        }

        if (!isSuccess) {
          print("❌ Inject failed: utd did not increase after retries.");
          return InjectResult(result: false, utd: afterutd, id: id);
        }

// ✅ Successful inject confirmed
        return InjectResult(result: true, utd: afterutd, id: id);
      } catch (e) {
        print("❌ Inject process error: $e");
        if (i == 2) {
          return InjectResult(result: false, utd: null, id: id);
        }
      }
    }
    return InjectResult(result: false, utd: null, id: id);
  }


  static Future<String> sendCommandAndListenProperly({
    required BluetoothDevice device,
    required String fullJson,
    required BluetoothCharacteristic notifyChar,
    required BluetoothCharacteristic writeChar,
  }) async {
    final completer = Completer<String>();
    await Future.delayed(const Duration(milliseconds: 200));

    // Enable notifications only if not already enabled
    if (!notifyChar.isNotifying) {
      await notifyChar.setNotifyValue(true);
    }

    // Start listening BEFORE sending
    final sub = notifyChar.onValueReceived.listen((data) {
      final response = utf8.decode(data);
      print("📨 Incoming Notify Data: $response");

      if (!completer.isCompleted) {
        completer.complete(response);
      }
    });

    // Send the command
    final payload = utf8.encode(fullJson);
    await writeChar.write(payload, withoutResponse: writeChar.properties.writeWithoutResponse);

    try {
      final result = await completer.future.timeout(Duration(seconds: 2));
      await sub.cancel();
      return result;
    } catch (e) {
      await sub.cancel();
      throw Exception("⏱️ Timeout or failed: $e");
    }
  }



  /// Helper to sign JSON and wrap with signature
  static String _wrapWithSignature(
      BluetoothDevice device,
      String password,
      List<Map<String, dynamic>> payloadList,
      ) {
    final jsonPayload = jsonEncode(payloadList.first);
    final controllerMac = device.remoteId.str.toUpperCase().replaceAll(':', '-');

    // Extract macaddress from payload (this is the pulse injector MAC)
    final injectorMac = _extractMacAddressFromPayload(payloadList);

    final input = "$controllerMac$injectorMac$jsonPayload";
    final signature = sha256.convert(utf8.encode(input)).toString();
    print('controllermac : ${controllerMac}, injectormac : ${injectorMac}');
    final fullJson = jsonEncode([
      ...payloadList,
      {"signature": signature}
    ]);

    print("🔐 Sending: $fullJson");
    return fullJson;
  }

  static String _extractMacAddressFromPayload(List<Map<String, dynamic>> payloadList) {
    try {
      final mac = payloadList.first["data"]["macaddress"];
      return (mac ?? "").toString().toUpperCase().replaceAll(':', '-');;
    } catch (e) {
      print("⚠️ Failed to extract injector MAC from payload: $e");
      return "";
    }
  }

}
