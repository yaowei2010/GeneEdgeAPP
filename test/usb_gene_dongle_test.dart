import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geneapp/usb_gene_dongle.dart';

Map<String, Object?> wire(int revision, String state,
        {Object? imported, String? errorCode}) =>
    {
      'revision': revision,
      'state': state,
      'volumes': [
        {'id': 'ABCD-1234', 'label': 'Gene dongle', 'authorized': true}
      ],
      'imported': imported,
      'errorCode': errorCode,
    };

const imported = {
  'datasetId': 'dataset-1',
  'sourceUri': 'content://com.android.externalstorage.documents/tree/ABCD-1234',
  'folderName': 'gene',
  'idsBytes': 12,
  'idxBytes': 15,
};

class FakePlatform implements UsbGeneDonglePlatform {
  final stream = StreamController<Object?>.broadcast(sync: true);
  Future<Object?> Function()? onRefresh;
  Future<Object?> Function(String)? onAccess;
  int refreshCalls = 0;
  int accessCalls = 0;
  @override
  Stream<Object?> get events => stream.stream;
  @override
  Future<Object?> refresh() async {
    refreshCalls++;
    return onRefresh == null ? wire(1, 'no_device') : await onRefresh!();
  }

  @override
  Future<Object?> requestAccess({required String volumeId}) async {
    accessCalls++;
    return onAccess == null
        ? wire(2, 'permission_required', errorCode: 'permission_denied')
        : await onAccess!(volumeId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('method adapter uses native contract and volumeId argument', () async {
    const channel = MethodChannel('geneedge/usb_gene_dongle');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return wire(1, 'no_device');
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final platform = MethodChannelUsbGeneDonglePlatform();
    expect(MethodChannelUsbGeneDonglePlatform.eventChannelName,
        'geneedge/usb_gene_dongle/events');
    await platform.refresh();
    await platform.requestAccess(volumeId: 'ABCD-1234');
    expect(calls.map((call) => call.method), ['refresh', 'requestAccess']);
    expect(calls.last.arguments, {'volumeId': 'ABCD-1234'});
  });

  test('parses typed snapshot and preserves last import after removal', () {
    final ready =
        UsbGeneDongleSnapshot.fromMap(wire(3, 'ready', imported: imported));
    expect(ready.state, UsbGeneDongleState.ready);
    expect(ready.imported!.idsBytes, 12);
    expect(ready.volumes.single.authorized, true);
    expect(
        UsbGeneDongleSnapshot.fromMap(wire(4, 'no_device', imported: imported))
            .imported!
            .datasetId,
        'dataset-1');
  });

  test('rejects malformed snapshot instead of fabricating ready', () {
    for (final value in [
      {...wire(1, 'ready'), 'revision': 1.5},
      wire(1, 'unknown'),
      wire(1, 'ready'),
      wire(1, 'ready', imported: {...imported, 'idxBytes': 0}),
      {
        ...wire(1, 'no_device'),
        'volumes': [
          {'id': 'x', 'label': 'x', 'authorized': 'yes'}
        ]
      },
    ]) {
      expect(() => UsbGeneDongleSnapshot.fromMap(value), throwsFormatException);
    }
  });

  test('start is idempotent and newer event wins over startup reply', () async {
    final platform = FakePlatform();
    final reply = Completer<Object?>();
    platform.onRefresh = () => reply.future;
    final controller =
        UsbGeneDongleController(platform: platform, supported: true);
    final first = controller.start();
    final duplicate = controller.start();
    expect(platform.refreshCalls, 1);
    platform.stream.add(wire(6, 'ready', imported: imported));
    reply.complete(wire(5, 'no_device'));
    await Future.wait([first, duplicate]);
    expect(controller.snapshot.revision, 6);
    expect(controller.snapshot.state, UsbGeneDongleState.ready);
    controller.dispose();
    expect(platform.stream.hasListener, false);
    await platform.stream.close();
  });

  test('refresh follows events and cancellation is observable', () async {
    final platform = FakePlatform();
    final controller =
        UsbGeneDongleController(platform: platform, supported: true);
    await controller.start();
    platform.stream.add(wire(3, 'scanning'));
    expect(controller.busy, true);
    platform.onRefresh = () async => wire(4, 'missing_files');
    await controller.refresh();
    expect(controller.snapshot.state, UsbGeneDongleState.missingFiles);
    platform.onAccess = (id) async {
      expect(id, 'ABCD-1234');
      return wire(5, 'permission_required', errorCode: 'permission_denied');
    };
    await controller.requestAccess('ABCD-1234');
    expect(controller.snapshot.errorCode, 'permission_denied');
    expect(controller.busy, false);
    controller.dispose();
    await platform.stream.close();
  });

  test('newer refresh event survives late failure and malformed stale reply',
      () async {
    final platform = FakePlatform();
    final controller =
        UsbGeneDongleController(platform: platform, supported: true);
    await controller.start();
    final failedReply = Completer<Object?>();
    platform.onRefresh = () => failedReply.future;
    final refresh = controller.refresh();
    platform.stream.add(wire(6, 'ready', imported: imported));
    failedReply.completeError(PlatformException(code: 'io_failed'));
    await refresh;
    expect(controller.snapshot.state, UsbGeneDongleState.ready);
    platform.onRefresh = () async => {'revision': 5, 'state': 'invalid'};
    await controller.refresh();
    expect(controller.snapshot.revision, 6);
    expect(controller.snapshot.state, UsbGeneDongleState.ready);
    platform.stream.add(wire(7, 'no_device', imported: imported));
    expect(controller.snapshot.imported!.datasetId, 'dataset-1');
    controller.dispose();
    await controller.start();
    await controller.refresh();
    await controller.requestAccess('ABCD-1234');
    expect(platform.refreshCalls, 3);
    expect(platform.accessCalls, 0);
    await platform.stream.close();
  });

  test('single picker operation and late disposal replies do not notify',
      () async {
    final platform = FakePlatform();
    final controller =
        UsbGeneDongleController(platform: platform, supported: true);
    await controller.start();
    final reply = Completer<Object?>();
    platform.onAccess = (_) => reply.future;
    final pending = controller.requestAccess('ABCD-1234');
    final duplicate = controller.requestAccess('ABCD-1234');
    expect(platform.accessCalls, 1);
    int notifications = 0;
    controller.addListener(() => notifications++);
    controller.dispose();
    reply.complete(wire(2, 'ready', imported: imported));
    await Future.wait([pending, duplicate]);
    expect(notifications, 0);
    expect(controller.snapshot.state, UsbGeneDongleState.noDevice);
    await platform.stream.close();
  });

  test('unsupported does not touch channels or injected platform', () async {
    final platform = FakePlatform();
    final controller =
        UsbGeneDongleController(platform: platform, supported: false);
    await controller.start();
    await controller.refresh();
    await controller.requestAccess('ABCD-1234');
    expect(controller.snapshot.state, UsbGeneDongleState.unsupported);
    expect(platform.refreshCalls + platform.accessCalls, 0);
    expect(platform.stream.hasListener, false);
    controller.dispose();
    await platform.stream.close();
  });

  test('malformed event and stream/platform errors become safe errors',
      () async {
    final platform = FakePlatform();
    final controller =
        UsbGeneDongleController(platform: platform, supported: true);
    await controller.start();
    platform.stream.add({'state': 'ready'});
    expect(controller.snapshot.state, UsbGeneDongleState.error);
    expect(controller.snapshot.errorCode, 'invalid_snapshot');
    platform.stream.add(wire(3, 'ready', imported: imported));
    platform.stream.addError(StateError('private details'));
    expect(controller.snapshot.errorCode, 'io_failed');
    expect(controller.snapshot.imported!.datasetId, 'dataset-1');
    platform.onRefresh = () =>
        throw PlatformException(code: 'cancelled', message: 'private details');
    await controller.refresh();
    expect(controller.snapshot.errorCode, 'cancelled');
    controller.dispose();
    await platform.stream.close();
  });
}
