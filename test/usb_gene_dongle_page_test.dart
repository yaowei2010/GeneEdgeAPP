import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geneapp/api_service.dart';
import 'package:geneapp/chat_controller.dart';
import 'package:geneapp/chat_room_page.dart';
import 'package:geneapp/usb_gene_dongle.dart';
import 'package:geneapp/usb_gene_dongle_page.dart';
import 'package:provider/provider.dart';

Map<String, Object?> snapshot(int revision, String state,
        {Object? imported, String? errorCode}) =>
    {
      'revision': revision,
      'state': state,
      'volumes': [
        {'id': 'ABCD-1234', 'label': 'Gene dongle', 'authorized': false},
      ],
      'imported': imported,
      'errorCode': errorCode,
    };

class PageUsbPlatform implements UsbGeneDonglePlatform {
  final updates = StreamController<Object?>.broadcast();
  Object? current = snapshot(1, 'permission_required');
  int refreshes = 0;
  String? requestedVolume;

  @override
  Stream<Object?> get events => updates.stream;

  @override
  Future<Object?> refresh() async {
    refreshes++;
    return current;
  }

  @override
  Future<Object?> requestAccess({required String volumeId}) async {
    requestedVolume = volumeId;
    return snapshot(2, 'permission_required', errorCode: 'permission_denied');
  }
}

void main() {
  late PageUsbPlatform platform;
  late UsbGeneDongleController usb;

  setUp(() {
    platform = PageUsbPlatform();
    usb = UsbGeneDongleController(platform: platform, supported: true);
  });

  tearDown(() async {
    usb.dispose();
    await platform.updates.close();
  });

  Future<void> showPage(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: UsbGeneDonglePage(controller: usb),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'new removable device exposes folder authorization and cancellation',
      (tester) async {
    await showPage(tester);
    expect(find.text('需要資料夾授權'), findsOneWidget);
    await tester.tap(find.text('授權資料夾'));
    await tester.pumpAndSettle();
    expect(platform.requestedVolume, 'ABCD-1234');
    expect(find.text('尚未授權，可再次選擇資料夾。'), findsOneWidget);
  });

  testWidgets('ready shows raw pair metadata, removal preserves last import',
      (tester) async {
    final imported = {
      'datasetId': 'dataset-test',
      'sourceUri':
          'content://com.android.externalstorage.documents/tree/ABCD-1234%3Agenes',
      'folderName': 'genes',
      'idsBytes': 12,
      'idxBytes': 24,
    };
    platform.current = snapshot(2, 'ready', imported: imported);
    await showPage(tester);
    expect(find.text('資料已匯入'), findsOneWidget);
    expect(find.text('combined_ids_all.txt'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('combined_idx_all.txt'), 150,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('combined_idx_all.txt'), findsOneWidget);
    expect(find.text('12 bytes'), findsOneWidget);
    expect(find.text('24 bytes'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text(imported['sourceUri']! as String),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(imported['sourceUri']! as String), findsOneWidget);
    platform.updates.add({
      ...snapshot(3, 'no_device', imported: imported),
      'volumes': <Object?>[],
    });
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('未偵測到 USB 儲存裝置'), -150,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('未偵測到 USB 儲存裝置'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('上次匯入的資料'), 150,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('上次匯入的資料'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('combined_ids_all.txt'), 150,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('combined_ids_all.txt'), findsOneWidget);
  });

  testWidgets('missing and ambiguous remain recoverable with refresh',
      (tester) async {
    platform.current = snapshot(2, 'missing_files');
    await showPage(tester);
    expect(find.text('找不到完整的雙檔資料'), findsOneWidget);
    final before = platform.refreshes;
    await tester.tap(find.text('重新掃描'));
    await tester.pumpAndSettle();
    expect(platform.refreshes, before + 1);
    platform.updates.add(snapshot(3, 'ambiguous'));
    await tester.pumpAndSettle();
    expect(find.text('找到多組資料，請縮小授權範圍'), findsOneWidget);
  });

  testWidgets('chat drawer opens independent USB page without calling AI',
      (tester) async {
    final chat = ChatController(api: _NoApiCalls(), threadId: 'usb-page-test');
    addTearDown(chat.dispose);
    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider.value(
        value: chat,
        child: ChatRoomPage(usbGeneDongle: usb),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('USB / Gene dongle'));
    await tester.tap(find.text('USB / Gene dongle'));
    await tester.pumpAndSettle();
    expect(find.byType(UsbGeneDonglePage), findsOneWidget);
    expect(find.text('需要資料夾授權'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chat resumes USB scanning after returning to foreground',
      (tester) async {
    final chat =
        ChatController(api: _NoApiCalls(), threadId: 'usb-resume-test');
    addTearDown(chat.dispose);
    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider.value(
        value: chat,
        child: ChatRoomPage(usbGeneDongle: usb),
      ),
    ));
    await tester.pumpAndSettle();
    final before = platform.refreshes;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(platform.refreshes, before + 1);
  });
}

class _NoApiCalls extends Fake implements ApiService {}
