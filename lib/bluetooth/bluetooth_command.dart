import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';


class InjectResult {
  final bool result;
  final int? utd1;
  final int id;

  InjectResult({
    required this.result,
    required this.utd1,
    required this.id,
  });
}

int? _extractUtd1FromPolling(List<dynamic>? responseList) {
  try {
    if (responseList == null || responseList.isEmpty) return null;

    final pollingData = responseList.firstWhere(
          (item) =>
      item is Map<String, dynamic> && item["commandcode"] == "polling",
      orElse: () => null,
    );

    if (pollingData == null || pollingData["data"] == null) return null;

    return int.tryParse(pollingData["data"]["utd1"].toString());
  } catch (e) {
    print("❌ Error parsing utd1: $e");
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
  }) async {
    if (id < 1 || id > 16) throw ArgumentError('ID must be between 1 and 16');

    final unixTime = (DateTime
        .now()
        .millisecondsSinceEpoch ~/ 1000).toString();
    final dataPayload = {
      "commandcode": "polling",
      "data": {
        "unixtime": unixTime,
        "id": id.toString(),
      },
    };

    final fullJson = _wrapWithSignature(device, password, [dataPayload]);

    try {
      final response = await BluetoothUtils.sendCommandAndListenProperly(
        device: device,
        fullJson: fullJson,
      );

      final parsed = jsonDecode(response);
      if (parsed is List && parsed.isNotEmpty) {
        final data = parsed[0]['data'];
        if (data is Map && data['status'] == 'present') {
          return {
            "id": int.parse(data['id']),
            "utd1": data['utd1'],
            "utd2": data['utd2'],
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
  }) async {
    try {
      await Future.delayed(const Duration(milliseconds: 500));
      // Step 1: Initial polling to get utd1
      final initialPollingResponse = await sendPollingCommand(
        device: device,
        id: id,
        password: password,
      );
      final initialUtd1 = int.tryParse(initialPollingResponse?["utd1"] ?? "");
      await Future.delayed(const Duration(milliseconds: 250));
      if (initialUtd1 == null) {
        print("❌ Initial polling failed or utd1 not found.");
        return InjectResult(result: false, utd1: null, id: id);
      }

      // Step 2: Inject command
      final unixTime = (DateTime
          .now()
          .millisecondsSinceEpoch ~/ 1000).toString();
      final dataPayload = {
        "commandcode": "inject",
        "data": {
          "unixtime": unixTime,
          "id": id.toString(),
          "channel": channel.toString(),
          "counter": counter.toString(),
        },
      };
      final fullJson = await _wrapWithSignature(
          device, password, [dataPayload]);

      final injectResponse = await BluetoothUtils.sendCommandAndListenProperly(
        device: device,
        fullJson: fullJson,
      );
      await Future.delayed(const Duration(milliseconds: 350));
      print("📥 Inject Response: $injectResponse");

      // Step 3: After polling
      final afterPollingResponse = await sendPollingCommand(
        device: device,
        id: id,
        password: password,
      );
      int? afterUtd1 = int.tryParse(afterPollingResponse?["utd1"] ?? "");

      if (afterUtd1 == null) {
        print("❌ After polling failed or utd1 not found.");
        return InjectResult(result: false, utd1: null, id: id);
      }

      // Step 4: Compare utd1
      bool isSuccess = false;


      for (int attempt = 1; attempt <= 3; attempt++) {
        final afterPollingResponse = await BluetoothUtils.sendPollingCommand(
          device: device,
          id: id,
          password: password,
        );

        afterUtd1 = int.tryParse(afterPollingResponse?["utd1"] ?? "");

        if (afterUtd1 != null && afterUtd1 > initialUtd1) {
          isSuccess = true;
          break; // ✅ Success
        }

        print("⚠️ Attempt $attempt: UTD1 not updated. Retrying...");
        await Future.delayed(const Duration(milliseconds: 250));
      }

      if (!isSuccess) {
        print("❌ Inject failed: UTD1 did not increase after retries.");
        return InjectResult(result: false, utd1: afterUtd1, id: id);
      }

// ✅ Successful inject confirmed
      return InjectResult(result: true, utd1: afterUtd1, id: id);
    } catch (e) {
      print("❌ Inject process error: $e");
      return InjectResult(result: false, utd1: null, id: id);
    }
  }


  static Future<String> sendCommandAndListenProperly({
    required BluetoothDevice device,
    required String fullJson,
  }) async {
    final services = await device.discoverServices();
    final service = services.firstWhere((s) => s.uuid == _serviceUuid);
    final notifyChar = service.characteristics.firstWhere((c) =>
    c.uuid == _notifyCharUuid);
    final writeChar = service.characteristics.firstWhere((c) =>
    c.uuid == _writeCharUuid);

    final completer = Completer<String>();

    // Enable notifications
    await notifyChar.setNotifyValue(true);

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
    if (writeChar.properties.writeWithoutResponse) {
      await writeChar.write(payload, withoutResponse: true);
    } else {
      await writeChar.write(payload, withoutResponse: false);
    }
    // await Future.delayed(const Duration(milliseconds: 50));
    try {
      // Wait for response or timeout
      final result = await completer.future.timeout(Duration(seconds: 2));
      await sub.cancel();
      return result;
    } catch (e) {
      await sub.cancel();
      throw Exception("⏱️ Timeout or failed: $e");
    }
  }


  /// Helper to sign JSON and wrap with signature
  static String _wrapWithSignature(BluetoothDevice device,
      String password,
      List<Map<String, dynamic>> payloadList,) {
    final jsonPayload = jsonEncode(payloadList.first); // Just the object
    final mac = device.remoteId.str.toLowerCase();
    final input = "$mac$password$jsonPayload";
    final signature = sha256.convert(utf8.encode(input)).toString();

    final fullJson = jsonEncode([
      ...payloadList,
      {"signature": signature}
    ]);

    print("🔐 Sending: $fullJson");
    return fullJson;
  }


}
