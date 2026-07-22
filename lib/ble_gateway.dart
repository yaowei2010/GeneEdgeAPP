import "dart:async";
import "dart:convert";
import "dart:io";
import "package:flutter/foundation.dart";
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

class _BleTerminalException implements Exception {
  final String message;

  const _BleTerminalException(this.message);

  @override
  String toString() => message;
}

class BleGateway {
  void _log(String message) {
    if (kDebugMode) {
      debugPrint("[BLE] $message");
    }
  }

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
    final fallbackCandidates = <String, ({BluetoothDevice dev, int rssi})>{};

    _log("scan start service=${AppConfig.serviceUuid}");
    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: AppConfig.scanSeconds),
      androidUsesFineLocation: true,
    );

    final sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final id = r.device.remoteId.str;
        final advName = r.advertisementData.advName;
        final platformName = r.device.platformName;
        final hasService =
            r.advertisementData.serviceUuids.contains(AppConfig.serviceUuid);
        final looksLikeEdge = _looksLikePreferredDevice(platformName) ||
            _looksLikePreferredDevice(advName);
        final row = (dev: r.device, rssi: r.rssi);

        if (hasService || looksLikeEdge) {
          final prev = candidates[id];
          if (prev == null || r.rssi > prev.rssi) {
            candidates[id] = row;
            _log(
              "candidate id=$id rssi=${r.rssi} platform=$platformName adv=$advName service=$hasService",
            );
          }
          continue;
        }

        final prevFallback = fallbackCandidates[id];
        if (prevFallback == null || r.rssi > prevFallback.rssi) {
          fallbackCandidates[id] = row;
        }
      }
    });

    await Future.delayed(const Duration(seconds: AppConfig.scanSeconds));
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await sub.cancel();

    if (candidates.isEmpty && fallbackCandidates.isNotEmpty) {
      _log(
        "no advertised Edge service/name found; falling back to ${fallbackCandidates.length} nearby device(s)",
      );
      candidates.addAll(fallbackCandidates);
    }

    if (candidates.isEmpty) {
      throw Exception(
        "No GeneEdge BLE device found. Make sure Edge is powered on, in pairing/advertising mode, and advertising service UUID ${AppConfig.serviceUuid}.",
      );
    }

    final rows = candidates.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    _log("scan done candidates=${rows.length}");

    return rows;
  }

  bool _looksLikePreferredDevice(String name) {
    final normalized = name.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    final prefix = AppConfig.preferredNamePrefix.toLowerCase();
    return prefix.isNotEmpty && normalized.startsWith(prefix);
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

    Object? lastError;
    for (final dev in devices) {
      for (var attempt = 1; attempt <= 3; attempt += 1) {
        _log(
          "connect attempt=$attempt id=${dev.remoteId.str} name=${dev.platformName}",
        );
        try {
          await dev.disconnect();
        } catch (_) {}

        await Future.delayed(
          Duration(milliseconds: Platform.isAndroid ? 900 : 250),
        );

        try {
          await dev.connect(
            timeout: const Duration(seconds: 30),
            autoConnect: false,
          );

          await dev.connectionState
              .timeout(const Duration(seconds: 20))
              .firstWhere((s) => s == BluetoothConnectionState.connected);

          await Future.delayed(
            Duration(milliseconds: Platform.isAndroid ? 900 : 500),
          );
          final (cmd, res, off) = await _findChars(dev);
          _log("connected id=${dev.remoteId.str}");
          return (dev, cmd, res, off);
        } catch (e) {
          lastError = e;
          _log(
              "connect failed id=${dev.remoteId.str} attempt=$attempt error=$e");
          try {
            await dev.disconnect();
          } catch (_) {}
          await Future.delayed(
            Duration(milliseconds: Platform.isAndroid ? 1200 * attempt : 300),
          );
        }
      }
    }

    throw Exception(
      "No compatible BLE gateway found (missing service/characteristics or connect failed). Last error: $lastError",
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
    _log("write command bytes=${bytes.length}");
    for (var i = 0; i < bytes.length; i += chunkSize) {
      final end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
      await c
          .write(bytes.sublist(i, end), withoutResponse: false)
          .timeout(const Duration(seconds: 8));
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
    _log("read result start timeout=${timeout.inSeconds}s");

    while (true) {
      if (DateTime.now().isAfter(deadline)) {
        throw Exception("Timeout waiting for BLE result");
      }

      await offChar
          .write(
            utf8.encode(offset.toString()),
            withoutResponse: false,
          )
          .timeout(const Duration(seconds: 8));

      final bytes = await resChar.read().timeout(const Duration(seconds: 8));
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

    final state = _inflateApiResponseIfNeeded(decoded);
    _log(
      "read result done bytes=${buffer.length} status=${state["status"]} job=${state["job_id"]}",
    );
    return state;
  }

  Future<void> _disconnectQuietly(BluetoothDevice? dev) async {
    if (dev == null) return;
    try {
      await dev.disconnect();
    } catch (_) {}
  }

  bool _isCurrentJob(Map<String, dynamic> state, String jobId) {
    return state["job_id"]?.toString() == jobId;
  }

  void _throwIfOtherRunningJob(Map<String, dynamic> state, String jobId) {
    final returnedJobId = state["job_id"]?.toString() ?? "";
    final status = state["status"]?.toString() ?? "";
    if (returnedJobId.isEmpty || returnedJobId == jobId) return;
    if (status == "running") {
      throw _BleTerminalException(
        "BLE gateway is busy with another job: $returnedJobId",
      );
    }
  }

  Map<String, dynamic>? _terminalResultForCurrentJob(
    Map<String, dynamic> state,
    String jobId,
  ) {
    final returnedJobId = state["job_id"]?.toString() ?? "";
    final status = state["status"]?.toString() ?? "";

    if (returnedJobId.isNotEmpty && returnedJobId != jobId) {
      if (status == "running") {
        throw _BleTerminalException(
          "BLE gateway is busy with another job: $returnedJobId",
        );
      }
      return null;
    }

    if (status == "done") return state;
    if (status == "error") {
      throw _BleTerminalException("BLE job error: ${state["error"]}");
    }
    return null;
  }

  Future<Map<String, dynamic>> runJobAndGetResult({
    required String jobId,
    required String query,
    required String topic,
    String? preferredDeviceId,
  }) async {
    BluetoothDevice? dev;
    BluetoothCharacteristic? cmdChar;
    BluetoothCharacteristic? resChar;
    BluetoothCharacteristic? offChar;
    var commandAccepted = false;
    var probeBeforeSend = false;
    var reconnectAttempt = 0;

    final cmd = {
      "job_id": jobId,
      "params": {"query": query, "topic": topic},
    };
    final cmdBytes = utf8.encode(jsonEncode(cmd));
    final overallDeadline = DateTime.now().add(const Duration(seconds: 320));

    Future<void> connect() async {
      final conn = await _connectToAnySupportedDevice(
        preferredDeviceId: preferredDeviceId,
      );
      dev = conn.$1;
      cmdChar = conn.$2;
      resChar = conn.$3;
      offChar = conn.$4;
    }

    Future<void> reconnectAfter(Object reason) async {
      await _disconnectQuietly(dev);
      dev = null;
      cmdChar = null;
      resChar = null;
      offChar = null;

      const delays = [
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 5),
        Duration(seconds: 10),
      ];

      Object lastError = reason;
      while (true) {
        if (DateTime.now().isAfter(overallDeadline)) {
          throw Exception(
            "Timeout waiting for BLE job result (overall): $lastError",
          );
        }

        final delay = delays[reconnectAttempt < delays.length
            ? reconnectAttempt
            : delays.length - 1];
        reconnectAttempt += 1;
        await Future.delayed(delay);

        try {
          await connect();
          probeBeforeSend = true;
          _log("reconnected after error=$lastError");
          return;
        } catch (e) {
          lastError = e;
          await _disconnectQuietly(dev);
          dev = null;
          cmdChar = null;
          resChar = null;
          offChar = null;
        }
      }
    }

    await connect();

    try {
      while (true) {
        if (DateTime.now().isAfter(overallDeadline)) {
          throw Exception("Timeout waiting for BLE job result (overall)");
        }

        try {
          if (!commandAccepted && probeBeforeSend) {
            final state = await _readResultChunked(
              resChar: resChar!,
              offChar: offChar!,
              timeout: const Duration(seconds: 12),
            );
            _throwIfOtherRunningJob(state, jobId);

            if (_isCurrentJob(state, jobId)) {
              commandAccepted = true;
              final terminal = _terminalResultForCurrentJob(state, jobId);
              if (terminal != null) return terminal;
            }
            probeBeforeSend = false;
          }

          if (!commandAccepted) {
            _log("send job=$jobId topic=$topic");
            await _safeWriteChunkedWithResponse(cmdChar!, cmdBytes);
            commandAccepted = true;
          }

          final state = await _readResultChunked(
            resChar: resChar!,
            offChar: offChar!,
            timeout: const Duration(seconds: 25),
          );

          final terminal = _terminalResultForCurrentJob(state, jobId);
          if (terminal != null) return terminal;

          reconnectAttempt = 0;
          await Future.delayed(const Duration(seconds: 1));
        } on _BleTerminalException {
          rethrow;
        } catch (e) {
          await reconnectAfter(e);
        }
      }
    } finally {
      await _disconnectQuietly(dev);
    }
  }
}
