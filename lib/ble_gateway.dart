import "dart:async";
import "dart:convert";
import "dart:io";
import "package:flutter_blue_plus/flutter_blue_plus.dart";
import "config.dart";

class BleDeviceOption {
  final String id;
  final String name;
  final int rssi;

  const BleDeviceOption({
    required this.id,
    required this.name,
    required this.rssi,
  });
}

class BleGateway {
  Future<void> _waitBluetoothReady() async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (true) {
      final state = await FlutterBluePlus.adapterState.first;

      if (state == BluetoothAdapterState.on) return;
      if (state == BluetoothAdapterState.off) {
        throw Exception(
          "Bluetooth is OFF. Please enable Bluetooth in iOS Settings.",
        );
      }
      if (state == BluetoothAdapterState.unauthorized) {
        throw Exception(
          "Bluetooth permission denied. Enable it in iOS Settings > GeneEdge > Bluetooth.",
        );
      }
      if (state == BluetoothAdapterState.unavailable) {
        throw Exception("Bluetooth is unavailable on this device.");
      }

      if (DateTime.now().isAfter(deadline)) {
        throw Exception(
          "Bluetooth state still not ready: $state. Check iOS Bluetooth permission and Info.plist settings.",
        );
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  Future<List<({BluetoothDevice dev, int rssi})>> _scanDeviceRows() async {
    await _waitBluetoothReady();

    final candidates = <String, ({BluetoothDevice dev, int rssi})>{};

    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: AppConfig.scanSeconds),
    );

    final sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final id = r.device.remoteId.str;
        final prev = candidates[id];
        if (prev == null || r.rssi > prev.rssi) {
          candidates[id] = (dev: r.device, rssi: r.rssi);
        }
      }
    });

    await Future.delayed(const Duration(seconds: AppConfig.scanSeconds));
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await sub.cancel();

    if (candidates.isEmpty) {
      throw Exception("No BLE devices found nearby.");
    }

    final rows = candidates.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));

    return rows;
  }

  List<BluetoothDevice> _prioritizeDevices(
    List<({BluetoothDevice dev, int rssi})> rows, {
    String? preferredDeviceId,
  }) {
    final preferred = <BluetoothDevice>[];
    final normal = <BluetoothDevice>[];

    if (preferredDeviceId != null && preferredDeviceId.isNotEmpty) {
      for (final row in rows) {
        if (row.dev.remoteId.str == preferredDeviceId) {
          preferred.add(row.dev);
        } else {
          normal.add(row.dev);
        }
      }
      return [...preferred, ...normal];
    }

    if (AppConfig.preferredNamePrefix.isEmpty) {
      return rows.map((e) => e.dev).toList();
    }

    final prefix = AppConfig.preferredNamePrefix.toLowerCase();
    for (final row in rows) {
      if (row.dev.platformName.toLowerCase().startsWith(prefix)) {
        preferred.add(row.dev);
      } else {
        normal.add(row.dev);
      }
    }
    return [...preferred, ...normal];
  }

  Future<List<BleDeviceOption>> scanNearbyDevices() async {
    final rows = await _scanDeviceRows();
    return rows
        .map(
          (e) => BleDeviceOption(
            id: e.dev.remoteId.str,
            name: e.dev.platformName.isEmpty ? "(no name)" : e.dev.platformName,
            rssi: e.rssi,
          ),
        )
        .toList();
  }

  Future<
      (
        BluetoothDevice dev,
        BluetoothCharacteristic cmd,
        BluetoothCharacteristic res,
        BluetoothCharacteristic off
      )> _connectToAnySupportedDevice({
    String? preferredDeviceId,
  }) async {
    final rows = await _scanDeviceRows();
    final devices = _prioritizeDevices(
      rows,
      preferredDeviceId: preferredDeviceId,
    );

    for (final dev in devices) {
      try {
        try {
          await dev.disconnect();
        } catch (_) {}

        await dev.connect(
          timeout: const Duration(seconds: 30),
          autoConnect: false,
        );

        await dev.connectionState
            .timeout(const Duration(seconds: 20))
            .firstWhere((s) => s == BluetoothConnectionState.connected);

        await Future.delayed(const Duration(milliseconds: 500));
        final (cmd, res, off) = await _findChars(dev);
        return (dev, cmd, res, off);
      } catch (_) {
        try {
          await dev.disconnect();
        } catch (_) {}
      }
    }

    throw Exception(
      "No compatible BLE gateway found (missing service/characteristics).",
    );
  }

  Future<
      (
        BluetoothCharacteristic cmd,
        BluetoothCharacteristic res,
        BluetoothCharacteristic off
      )> _findChars(BluetoothDevice dev) async {
    final services = await dev.discoverServices();

    BluetoothCharacteristic? cmdChar;
    BluetoothCharacteristic? resChar;
    BluetoothCharacteristic? offChar;

    for (final s in services) {
      if (s.uuid == AppConfig.serviceUuid) {
        for (final c in s.characteristics) {
          if (c.uuid == AppConfig.cmdUuid) cmdChar = c;
          if (c.uuid == AppConfig.resUuid) resChar = c;
          if (c.uuid == AppConfig.offUuid) offChar = c;
        }
      }
    }

    if (cmdChar == null || resChar == null || offChar == null) {
      throw Exception("Missing CMD / RES / OFF characteristic. Check UUIDs.");
    }

    return (cmdChar, resChar, offChar);
  }

  Future<void> _safeWriteChunkedWithResponse(
    BluetoothCharacteristic c,
    List<int> bytes,
  ) async {
    const chunkSize = 20;
    for (var i = 0; i < bytes.length; i += chunkSize) {
      final end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
      await c.write(bytes.sublist(i, end), withoutResponse: false);
      await Future.delayed(const Duration(milliseconds: 30));
    }
  }

  Map<String, dynamic> _inflateApiResponseIfNeeded(Map<String, dynamic> state) {
    final b64 = state["api_response_gz_b64"];
    if (b64 is! String) return state;

    try {
      final gzBytes = base64Decode(b64);
      final rawBytes = GZipCodec().decode(gzBytes);
      final rawStr = utf8.decode(rawBytes);
      final apiResp = jsonDecode(rawStr);
      state["api_response"] = apiResp;
    } catch (e) {
      state["api_response"] = null;
      state["error"] = "inflate api_response failed: $e";
      state["status"] = "error";
    }

    return state;
  }

  Future<Map<String, dynamic>> _readResultChunked({
    required BluetoothCharacteristic resChar,
    required BluetoothCharacteristic offChar,
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    final buffer = <int>[];
    var offset = 0;

    while (true) {
      if (DateTime.now().isAfter(deadline)) {
        throw Exception("Timeout waiting for BLE result");
      }

      await offChar.write(
        utf8.encode(offset.toString()),
        withoutResponse: false,
      );

      final bytes = await resChar.read();
      if (bytes.isEmpty) {
        await Future.delayed(const Duration(milliseconds: 120));
        continue;
      }

      final header = bytes.first;
      final chunk = bytes.sublist(1);

      buffer.addAll(chunk);
      offset += chunk.length;

      if (header == 1) break;
      await Future.delayed(const Duration(milliseconds: 80));
    }

    final jsonStr = utf8.decode(buffer, allowMalformed: true);
    final decoded = jsonDecode(jsonStr);
    if (decoded is! Map<String, dynamic>) {
      throw Exception("BLE result JSON is not an object");
    }

    return _inflateApiResponseIfNeeded(decoded);
  }

  Future<Map<String, dynamic>> runJobAndGetResult({
    required String jobId,
    required String query,
    required String topic,
    String? preferredDeviceId,
  }) async {
    final (dev, cmdChar, resChar, offChar) = await _connectToAnySupportedDevice(
        preferredDeviceId: preferredDeviceId);

    try {
      final cmd = {
        "job_id": jobId,
        "params": {"query": query, "topic": topic},
      };

      final cmdBytes = utf8.encode(jsonEncode(cmd));
      await _safeWriteChunkedWithResponse(cmdChar, cmdBytes);

      final overallDeadline = DateTime.now().add(const Duration(seconds: 320));

      while (true) {
        if (DateTime.now().isAfter(overallDeadline)) {
          throw Exception("Timeout waiting for BLE job result (overall)");
        }

        final state = await _readResultChunked(
          resChar: resChar,
          offChar: offChar,
          timeout: const Duration(seconds: 25),
        );

        final status = (state["status"] ?? "").toString();

        if (status == "done") return state;
        if (status == "error") {
          throw Exception("BLE job error: ${state["error"]}");
        }

        await Future.delayed(const Duration(seconds: 1));
      }
    } finally {
      try {
        await dev.disconnect();
      } catch (_) {}
    }
  }
}
