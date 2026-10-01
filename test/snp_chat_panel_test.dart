import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geneapp/api_service.dart';
import 'package:geneapp/chat_controller.dart';
import 'package:geneapp/chat_room_page.dart';
import 'package:geneapp/models.dart';
import 'package:geneapp/snp_compute.dart';
import 'package:geneapp/snp_compute_page.dart';
import 'package:geneapp/snp_chat_panel.dart';
import 'package:geneapp/snp_sets.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'snp_locus_compute_test.dart' show FakeLocusPlatform, locusWire;

class NoAi extends Fake implements ApiService {}

class ChatUsbPlatform extends FakeLocusPlatform {
  Future<Object?> Function()? onSources;
  @override
  Future<Object?> sources() => onSources?.call() ?? super.sources();
  Future<Object?> Function(String)? onAccess, onSelect;
  int accessCalls = 0, selectCalls = 0;
  String? lastVolume;
  @override
  Future<Object?> requestAccess(String id) async {
    accessCalls++;
    lastVolume = id;
    return onAccess == null ? sourceState : await onAccess!(id);
  }

  @override
  Future<Object?> selectSource(String id) async {
    selectCalls++;
    return onSelect == null ? sourceState : await onSelect!(id);
  }

  Map<String, Object?> sourceState = {
    'revision': 1,
    'sources': [
      {'id': 'usb1', 'label': 'USB / gene'}
    ],
    'volumes': [
      {
        'id': 'usb-volume',
        'label': 'USB',
        'authorized': true,
        'authorizationScopes': ['USB 根目錄']
      }
    ],
    'selectedSourceId': 'usb1'
  };
  @override
  Map<String, Object?> sourcesMap() => sourceState;
}

class NoHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('Offline must not use HTTP');
}

void main() {
  testWidgets(
      'pending preference hides JSON; late load cannot override user toggle; only bool persists',
      (tester) async {
    final semantics = tester.ensureSemantics();
    SharedPreferences.setMockInitialValues({'snp_chat_show_api_json': true});
    final prefs = await SharedPreferences.getInstance();
    final load = Completer<SharedPreferences>();
    final queries = SnpSets.alcohol
        .parse(File(SnpSets.alcohol.assetPath!).readAsBytesSync());
    final p = ChatUsbPlatform();
    final c = SnpComputeController(platform: p, supported: true);
    final chat = ChatController(api: NoAi(), threadId: 'preference');
    await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider.value(
            value: chat,
            child: ChatRoomPage(
                snpCompute: c,
                snpSetLoader: (_) async => queries,
                snpPreferencesLoader: () => load.future))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用此 USB'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'private query');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    p.stream.add({
      'revision': 2,
      'jobId': 'job1',
      'status': 'completed',
      'mode': 'locus',
      'completed': 77,
      'total': 77,
      'results': SnpLocus.group(queries).map(locusWire).toList()
    });
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byType(SnpChatResultCard),
            matching: find.byType(SelectableText)),
        findsNothing);
    await tester.tap(find.byTooltip('開啟設定'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('顯示 API JSON'));
    await tester.tap(find.text('顯示 API JSON'));
    await tester.pump();
    load.complete(prefs);
    await tester.pumpAndSettle();
    expect(find.text('已完成，API JSON 已隱藏'), findsOneWidget);
    expect(prefs.getKeys(), {'snp_chat_show_api_json'});
    expect(prefs.getBool('snp_chat_show_api_json'), false);
    expect(c.locusResults.length, 77);
    expect(p.runCalls, 1);
    expect(find.text('查看 debug／分段計時'), findsNothing);
    await tester.enterText(find.byType(TextField), 'second private query');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    final visibility = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, '顯示 API JSON'));
    expect(visibility.onChanged, isNotNull);
    expect(visibility.value, false);
    p.stream.add({
      'revision': 3,
      'jobId': 'job1',
      'status': 'completed',
      'mode': 'locus',
      'completed': 77,
      'total': 77,
      'results': SnpLocus.group(queries).map(locusWire).toList()
    });
    await tester.pumpAndSettle();
    expect(p.runCalls, 2);
    expect(find.text('已完成，API JSON 已隱藏'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(SnpChatResultCard),
            matching: find.byType(SelectableText)),
        findsNothing);
    expect(find.bySemanticsLabel(RegExp('"SNP_list"')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    final next = SnpComputeController(platform: p, supported: true);
    await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider.value(
            value: chat, child: ChatRoomPage(snpCompute: next))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('開啟設定'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<SwitchListTile>(
                find.widgetWithText(SwitchListTile, '顯示 API JSON'))
            .value,
        false);
    expect(next.locusResults, isEmpty);
    expect(find.byType(SnpChatResultCard), findsNothing);
    await tester.pumpWidget(const SizedBox());
    next.dispose();
    chat.dispose();
    await p.stream.close();
    semantics.dispose();
  });
  for (final saved in [false, 'invalid', null]) {
    testWidgets(
        'JSON display preference is type-safe and survives page entry: $saved',
        (tester) async {
      SharedPreferences.setMockInitialValues(
          {if (saved != null) 'snp_chat_show_api_json': saved});
      final p = ChatUsbPlatform();
      final c = SnpComputeController(platform: p, supported: true);
      final chat = ChatController(api: NoAi(), threadId: 'pref-type');
      await tester.pumpWidget(MaterialApp(
          home: ChangeNotifierProvider.value(
              value: chat, child: ChatRoomPage(snpCompute: c))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('開啟設定'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<SwitchListTile>(
                  find.widgetWithText(SwitchListTile, '顯示 API JSON'))
              .value,
          saved == null);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      chat.dispose();
      await p.stream.close();
    });
  }
  for (final invalidation in ['topic', 'cancel', 'logout', 'dispose']) {
    testWidgets(
        'explicit diagnostic closes on $invalidation without restoring stale result',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final p = ChatUsbPlatform();
      final c = SnpComputeController(platform: p, supported: true);
      final chat = ChatController(api: NoAi(), threadId: 'diagnostic');
      final queries = SnpSets.alcohol
          .parse(File(SnpSets.alcohol.assetPath!).readAsBytesSync());
      await tester.pumpWidget(MaterialApp(
          home: ChangeNotifierProvider.value(
              value: chat,
              child: ChatRoomPage(
                  snpCompute: c,
                  onLogout: () {},
                  snpSetLoader: (_) async => queries))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('使用此 USB'));
      await tester.pumpAndSettle();
      c.setDebugEnabled(true);
      await tester.enterText(find.byType(TextField), 'timing');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      final complete = {
        'revision': 2,
        'jobId': 'job1',
        'status': 'completed',
        'mode': 'locus',
        'completed': 77,
        'total': 77,
        'results': SnpLocus.group(queries)
            .map((q) => locusWire(q, debug: true))
            .toList(),
        'debugTiming': {
          'setupIoMs': 3.0,
          'queryIoMs': 539.0,
          'countMs': 385.0,
          'genotypeMs': 154.0,
          'overheadMs': 82.0,
          'totalMs': 1163.0
        }
      };
      p.stream.add(complete);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('開啟設定'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('查看 debug／分段計時'));
      await tester.tap(find.text('查看 debug／分段計時'));
      await tester.pumpAndSettle();
      expect(find.text('USB 診斷／分段計時'), findsOneWidget);
      if (invalidation == 'topic') {
        await chat.setTopic(ChatTopic.medication);
      } else if (invalidation == 'cancel') {
        await c.cancel();
      } else if (invalidation == 'logout') {
        await tester.tap(find.text('關閉'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('開啟選單'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Log out'));
        await tester.tap(find.text('Log out'));
      } else {
        await tester.pumpWidget(const SizedBox());
      }
      await tester.pumpAndSettle();
      expect(find.text('USB 診斷／分段計時'), findsNothing);
      expect(c.debugReport, isNull);
      p.stream.add({...complete, 'revision': 5});
      await tester.pumpAndSettle();
      expect(c.debugReport, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      chat.dispose();
      await p.stream.close();
    });
  }
  testWidgets(
      'USB detected while app inactive waits for foreground without topic tap',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final p = ChatUsbPlatform();
    final ready = p.sourceState;
    p.sourceState = {
      'revision': 1,
      'sources': [],
      'volumes': [],
      'selectedSourceId': null
    };
    final c = SnpComputeController(platform: p, supported: true);
    final chat = ChatController(
        api: NoAi(), threadId: 'foreground', topic: ChatTopic.medication);
    await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider.value(
            value: chat, child: ChatRoomPage(snpCompute: c))));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    p.sourceState = {...ready, 'revision': 2};
    await c.refresh();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('USB 使用確認'), findsOneWidget);
    expect(p.runCalls, 0);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    chat.dispose();
    await p.stream.close();
  });
  for (final topic in [ChatTopic.alcohol, ChatTopic.medication]) {
    testWidgets(
        'mount snapshot prompts without topic tap while scan/set pending: ${topic.key}',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final p = ChatUsbPlatform();
      p.sourceState = {
        'revision': 1,
        'sources': [],
        'volumes': [],
        'selectedSourceId': null
      };
      final c = SnpComputeController(platform: p, supported: true);
      final chat = ChatController(api: NoAi(), threadId: 'mount', topic: topic);
      final load = Completer<List<SnpQuery>>();
      await tester.pumpWidget(MaterialApp(
          home: ChangeNotifierProvider.value(
              value: chat,
              child: ChatRoomPage(
                  snpCompute: c, snpSetLoader: (_) => load.future))));
      await tester.pumpAndSettle();
      final scan = Completer<Object?>();
      p.onSources = () => scan.future;
      p.stream.add({'revision': 2, 'status': 'sourcesChanged'});
      p.stream.add({
        'revision': 3,
        'status': 'sourcesSnapshot',
        'scanning': true,
        'sources': [],
        'selectedSourceId': null,
        'volumes': [
          {'id': 'ABCD-1234', 'label': 'USB', 'authorized': true}
        ]
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('USB 使用確認'), findsOneWidget);
      expect(find.text('USB 來源掃描中'), findsOneWidget);
      expect(
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, '使用此 USB'))
              .onPressed,
          isNull);
      expect(chat.topic, topic);
      expect(p.runCalls, 0);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      scan.complete({
        'revision': 4,
        'sources': [],
        'selectedSourceId': null,
        'volumes': [
          {'id': 'ABCD-1234', 'label': 'USB', 'authorized': true}
        ]
      });
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      chat.dispose();
      await p.stream.close();
    });
  }
  testWidgets(
      'new USB under another route prompts on return without topic interaction',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final p = ChatUsbPlatform();
    final ready = p.sourceState;
    p.sourceState = {
      'revision': 1,
      'sources': [],
      'volumes': [],
      'selectedSourceId': null
    };
    final c = SnpComputeController(platform: p, supported: true);
    final chat = ChatController(
        api: NoAi(), threadId: 'route', topic: ChatTopic.medication);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        home: ChangeNotifierProvider.value(
            value: chat, child: ChatRoomPage(snpCompute: c))));
    await tester.pumpAndSettle();
    unawaited(nav.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('other route')))));
    await tester.pumpAndSettle();
    p.sourceState = {...ready, 'revision': 2};
    await c.refresh();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('USB 使用確認'), findsOneWidget);
    expect(p.runCalls, 0);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    chat.dispose();
    await p.stream.close();
  });
  testWidgets(
      'new USB while busy prompts only when idle; removed deferred USB stays gone',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final p = ChatUsbPlatform();
    final ready = p.sourceState;
    final c = SnpComputeController(platform: p, supported: true);
    final chat = ChatController(api: NoAi(), threadId: 'busy');
    await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider.value(
            value: chat, child: ChatRoomPage(snpCompute: c))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用此 USB'));
    await tester.pumpAndSettle();
    final q =
        SnpQuery.validated(id: 'rs1', sequence: 'A' * 301, ref: 'A', alt: 'C');
    await c.run([q]);
    p.sourceState = {
      ...ready,
      'revision': 2,
      'volumes': [
        ...(ready['volumes'] as List),
        {'id': 'ABCD-1234', 'label': 'new USB', 'authorized': false}
      ]
    };
    await c.refresh();
    await tester.pumpAndSettle();
    expect(c.busy, true);
    expect(find.byType(AlertDialog), findsNothing);
    await c.cancel();
    await tester.pumpAndSettle();
    expect(find.text('USB 使用確認'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    final nav = Navigator.of(tester.element(find.byType(ChatRoomPage)));
    unawaited(
        nav.push(MaterialPageRoute<void>(builder: (_) => const SizedBox())));
    await tester.pumpAndSettle();
    p.stream.add(
        {'revision': 3, 'status': 'invalidated', 'errorCode': 'USB_REMOVED'});
    await tester.pumpAndSettle();
    nav.pop();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    chat.dispose();
    await p.stream.close();
  });
  testWidgets(
      'multiple USBs require a volume and source choice; subfolder grant stays explicit',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final p = ChatUsbPlatform();
    p.sourceState = {
      'revision': 1,
      'selectedSourceId': null,
      'sources': [
        {'id': 'gene-a', 'label': 'gene A', 'volumeId': 'usb-a'},
        {'id': 'gene-b', 'label': 'gene B', 'volumeId': 'usb-b'}
      ],
      'volumes': [
        {
          'id': 'usb-a',
          'label': 'USB A',
          'authorized': true,
          'authorizationScopes': ['USB 根目錄']
        },
        {
          'id': 'usb-b',
          'label': 'USB B',
          'authorized': true,
          'authorizationScopes': ['子資料夾：gene B']
        }
      ]
    };
    p.onSelect = (id) async {
      p.sourceState = {
        ...p.sourceState,
        'revision': (p.sourceState['revision'] as int) + 1,
        'selectedSourceId': id
      };
      return p.sourceState;
    };
    final c = SnpComputeController(platform: p, supported: true);
    final chat = ChatController(api: NoAi(), threadId: 'multi');
    await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider.value(
            value: chat, child: ChatRoomPage(snpCompute: c))));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '使用此 USB'))
            .onPressed,
        isNull);
    expect(find.textContaining('沿用唯讀授權'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('usb-confirm-volume')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('USB B').last);
    await tester.pumpAndSettle();
    expect(find.text('沿用唯讀授權：子資料夾：gene B'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirm-source-usb-b-null')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('gene B').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用此 USB'));
    await tester.pumpAndSettle();
    expect(c.sourceConfirmed, true);
    expect(c.selectedSourceId, 'gene-b');
    expect(p.accessCalls, 0);
    expect(p.runCalls, 0);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    chat.dispose();
    await p.stream.close();
  });
  testWidgets(
      'root authorization reply updates the same dialog and later reuses grant',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final p = ChatUsbPlatform();
    final ready = p.sourceState;
    p.sourceState = {
      'revision': 1,
      'sources': [],
      'selectedSourceId': null,
      'volumes': [
        {
          'id': 'usb-volume',
          'label': 'USB',
          'authorized': false,
          'authorizationScopes': []
        }
      ]
    };
    p.onAccess = (_) async {
      p.sourceState = {...ready, 'revision': 2};
      return p.sourceState;
    };
    final c = SnpComputeController(platform: p, supported: true);
    final chat = ChatController(api: NoAi(), threadId: 'reuse');
    await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider.value(
            value: chat, child: ChatRoomPage(snpCompute: c))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('授權 USB 根目錄'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('沿用唯讀授權：USB 根目錄'), findsOneWidget);
    await c.refresh();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('使用此 USB'));
    await tester.pumpAndSettle();
    await c.refresh();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(p.accessCalls, 1);
    expect(p.runCalls, 0);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    chat.dispose();
    await p.stream.close();
  });
  for (final close in ['cancel', 'outside', 'back']) {
    testWidgets(
        'USB $close dismissal does not repeat; unplug/reinsert prompts again',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final p = ChatUsbPlatform();
      final initial = p.sourceState;
      final c = SnpComputeController(platform: p, supported: true);
      final chat = ChatController(api: NoAi(), threadId: close);
      await tester.pumpWidget(MaterialApp(
          home: ChangeNotifierProvider.value(
              value: chat, child: ChatRoomPage(snpCompute: c))));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      if (close == 'cancel') {
        await tester.tap(find.text('取消'));
      } else if (close == 'outside') {
        await tester.tapAt(const Offset(5, 5));
      } else {
        await tester.binding.handlePopRoute();
      }
      await tester.pumpAndSettle();
      await c.refresh();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(c.sourceConfirmed, false);
      expect(p.runCalls, 0);
      expect(p.accessCalls, 0);
      p.stream.add(
          {'revision': 2, 'status': 'invalidated', 'errorCode': 'USB_REMOVED'});
      p.sourceState = {
        'revision': 3,
        'sources': [],
        'volumes': [],
        'selectedSourceId': null
      };
      await c.refresh();
      await tester.pumpAndSettle();
      p.sourceState = {...initial, 'revision': 4};
      await c.refresh();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      c.dispose();
      chat.dispose();
      await p.stream.close();
    });
  }
  testWidgets(
      'USB root authorization is explicit; removal rejects late grant with keyboard open',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final p = ChatUsbPlatform();
    final ready = {...p.sourceState, 'revision': 4};
    p.sourceState = {
      'revision': 1,
      'sources': [],
      'selectedSourceId': null,
      'volumes': [
        {
          'id': 'usb-volume',
          'label': 'USB',
          'authorized': false,
          'authorizationScopes': []
        }
      ]
    };
    final grant = Completer<Object?>();
    p.onAccess = (_) => grant.future;
    final c = SnpComputeController(platform: p, supported: true);
    final chat = ChatController(api: NoAi(), threadId: 'grant');
    await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider.value(
            value: chat, child: ChatRoomPage(snpCompute: c))));
    await tester.pumpAndSettle();
    expect(find.text('預設位置：USB 根目錄'), findsOneWidget);
    expect(p.accessCalls, 0);
    await tester.ensureVisible(find.text('授權 USB 根目錄'));
    await tester.tap(find.text('授權 USB 根目錄'));
    await tester.pump();
    expect(p.accessCalls, 1);
    expect(p.lastVolume, 'usb-volume');
    expect(p.runCalls, 0);
    p.stream.add(
        {'revision': 2, 'status': 'invalidated', 'errorCode': 'USB_REMOVED'});
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    grant.complete(ready);
    await tester.pumpAndSettle();
    expect(c.sources, isEmpty);
    expect(c.sourceConfirmed, false);
    expect(find.byKey(const ValueKey('usb-source-icon')), findsNothing);
    expect(tester.takeException(), isNull);
    expect(p.runCalls, 0);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    chat.dispose();
    await p.stream.close();
  });
  testWidgets(
      'closing confirmation during native select never confirms after late reply',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final p = ChatUsbPlatform();
    final select = Completer<Object?>();
    p.onSelect = (_) => select.future;
    final c = SnpComputeController(platform: p, supported: true);
    final chat = ChatController(api: NoAi(), threadId: 'late-select');
    await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider.value(
            value: chat, child: ChatRoomPage(snpCompute: c))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用此 USB'));
    await tester.pump();
    await tester.tap(find.byTooltip('關閉 USB 確認'));
    await tester.pumpAndSettle();
    select.complete(p.sourceState);
    await tester.pumpAndSettle();
    expect(c.sourceConfirmed, false);
    expect(p.runCalls, 0);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    chat.dispose();
    await p.stream.close();
  });
  testWidgets(
      'USB insertion dialog can close, reopen, confirm and waits for send',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final p = ChatUsbPlatform();
    final c = SnpComputeController(platform: p, supported: true);
    final chat = ChatController(api: NoAi(), threadId: 'confirm');
    final queries = SnpSets.alcohol
        .parse(File(SnpSets.alcohol.assetPath!).readAsBytesSync());
    await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider.value(
            value: chat,
            child: ChatRoomPage(
                snpCompute: c, snpSetLoader: (_) => Future.value(queries)))));
    await tester.pumpAndSettle();
    expect(find.text('USB 使用確認'), findsOneWidget);
    expect(p.runCalls, 0);
    await tester.tap(find.byTooltip('關閉 USB 確認'));
    await tester.pumpAndSettle();
    await c.refresh();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
            .onPressed,
        isNull);
    await tester.tap(find.byKey(const ValueKey('usb-source-icon')));
    await tester.pumpAndSettle();
    expect(find.text('USB 使用確認'), findsOneWidget);
    await tester.tap(find.text('使用此 USB'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(p.runCalls, 0);
    await tester.enterText(find.byType(TextField), '我能喝酒嗎');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(p.runCalls, 1);
    expect(p.lastQueries.length, 143);
    expect(find.text('我能喝酒嗎'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    chat.dispose();
    await p.stream.close();
  });
  testWidgets(
      'USB header tooltip and bounded top settings never start computation',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final p = ChatUsbPlatform();
    p.sourceState = {
      ...p.sourceState,
      'sources': [
        {'id': 'content://private/tree/usb1', 'label': 'USB / gene'}
      ],
      'selectedSourceId': 'content://private/tree/usb1'
    };
    final c = SnpComputeController(platform: p, supported: true);
    final chat = ChatController(api: NoAi(), threadId: 'icon');
    final queries = SnpSets.alcohol
        .parse(File(SnpSets.alcohol.assetPath!).readAsBytesSync());
    await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider.value(
            value: chat,
            child: ChatRoomPage(
                snpCompute: c, snpSetLoader: (_) => Future.value(queries)))));
    await tester.pumpAndSettle();
    final icon = find.byKey(const ValueKey('usb-source-icon'));
    await tester.tap(find.text('使用此 USB'));
    await tester.pumpAndSettle();
    expect(icon, findsOneWidget);
    expect(find.text('USB 已就緒'), findsOneWidget);
    expect(find.text('Debug：結果與分段計時'), findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(icon));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('資料夾：USB / gene'), findsOneWidget);
    expect(find.text('usb1'), findsNothing);
    expect(find.textContaining('content://'), findsNothing);
    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    await tester.longPress(icon);
    await tester.pumpAndSettle();
    expect(find.textContaining('資料夾：USB / gene'), findsOneWidget);
    await tester.tap(icon);
    await tester.pumpAndSettle();
    expect(find.text('USB 使用確認'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('開啟設定'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(
        find.ancestor(of: icon, matching: find.byType(AppBar)), findsNothing);
    expect(find.byKey(const ValueKey('usb-top-settings')), findsOneWidget);
    await tester.tap(find.byTooltip('收合設定'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('usb-top-settings')), findsNothing);
    await tester.tap(find.byTooltip('開啟設定'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('usb-top-settings')), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Debug：結果與分段計時'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(p.runCalls, 0);
    await tester.longPress(icon);
    await tester.pumpAndSettle();
    expect(find.textContaining('資料夾：USB / gene'), findsOneWidget);
    p.sourceState = {
      ...p.sourceState,
      'revision': 2,
      'selectedSourceId': null,
      'sources': [
        {'id': 'usb1', 'label': 'USB / one'},
        {'id': 'usb2', 'label': 'USB / two'}
      ]
    };
    await c.refresh();
    await tester.pumpAndSettle();
    expect(find.textContaining('資料夾：USB / gene'), findsNothing);
    await tester.longPress(icon);
    await tester.pumpAndSettle();
    expect(find.textContaining('USB 已偵測，請授權或選取資料夾'), findsOneWidget);
    expect(find.textContaining('資料夾：USB /'), findsNothing);
    p.sourceState = {
      'revision': 3,
      'sources': [],
      'volumes': [],
      'selectedSourceId': null
    };
    await c.refresh();
    await tester.pumpAndSettle();
    expect(icon, findsNothing);
    expect(find.textContaining('USB 已偵測，請授權或選取資料夾'), findsNothing);
    expect(p.runCalls, 0);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    chat.dispose();
    await p.stream.close();
  });
  testWidgets(
      'chat sends alcohol set to offline C, presents 77 unique API rows and explicit clipboard without persistence',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final previous = HttpOverrides.current;
    HttpOverrides.global = NoHttp();
    addTearDown(() => HttpOverrides.global = previous);
    final queries = SnpSets.alcohol
        .parse(File(SnpSets.alcohol.assetPath!).readAsBytesSync());
    final p = FakeLocusPlatform();
    final compute = SnpComputeController(platform: p, supported: true);
    final chat = ChatController(api: NoAi(), threadId: 'chat-usb');
    chat.messages.add(ChatMessage(
        id: 'previous',
        role: Role.user,
        content: '上一則對話',
        createdAt: DateTime.now()));
    chat.geneLlmEnabled = true;
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider.value(
            value: chat,
            child: ChatRoomPage(
                snpCompute: compute,
                snpSetLoader: (_) => Future.value(queries)))));
    await tester.pumpAndSettle();
    expect(p.runCalls, 0);
    expect(find.text('USB 離線 SNP'), findsNothing);
    expect(find.text('上一則對話'), findsOneWidget);
    await tester.tap(find.text('使用此 USB'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('開啟設定'));
    await tester.pumpAndSettle();
    expect(find.textContaining('77 位點'), findsWidgets);
    expect(find.byType(SnpComputePage), findsNothing);
    await tester.ensureVisible(find.text('Debug：結果與分段計時'));
    await tester.tap(find.text('Debug：結果與分段計時'));
    await tester.pump();
    expect(p.runCalls, 0);
    await tester.enterText(find.byType(TextField), '我能喝酒嗎');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(p.lastQueries.length, 143);
    expect(p.lastDebug, true);
    expect(
        tester
            .widget<SwitchListTile>(
                find.widgetWithText(SwitchListTile, 'Debug：結果與分段計時'))
            .onChanged,
        isNull);
    await tester.ensureVisible(find.text('USB 來源已選定'));
    await tester.tap(find.text('USB 來源已選定'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<DropdownButtonFormField<String>>(
                find.byType(DropdownButtonFormField<String>))
            .onChanged,
        isNull);
    expect(
        tester
            .widget<TextButton>(find.ancestor(
                of: find.text('重新掃描 USB'),
                matching: find.byWidgetPredicate((w) => w is TextButton)))
            .onPressed,
        isNull);
    expect(chat.messages.map((m) => m.content), ['上一則對話']);
    expect(find.text('我能喝酒嗎'), findsOneWidget);
    expect(
        (tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send)))
            .onPressed,
        isNull);
    final loci = SnpLocus.group(queries);
    p.stream.add({
      'jobId': 'job1',
      'revision': 2,
      'status': 'completed',
      'completed': 77,
      'total': 77,
      'mode': 'locus',
      'results': loci.map((q) => locusWire(q, debug: true)).toList(),
      'debugTiming': {
        'setupIoMs': 3.0,
        'queryIoMs': 539.0,
        'countMs': 385.0,
        'genotypeMs': 154.0,
        'overheadMs': 82.0,
        'totalMs': 1163.0
      }
    });
    await tester.pumpAndSettle();
    expect(find.text('完成 77／77 位點'), findsOneWidget);
    expect(find.text('每位點 genotype／posterior'), findsNothing);
    expect(find.text('查看 debug 結果'), findsNothing);
    expect(find.textContaining('1163.000'), findsNothing);
    final apiText = find.descendant(
        of: find.byType(SnpChatResultCard),
        matching: find.byType(SelectableText));
    expect(apiText, findsOneWidget);
    expect(
        tester.getSize(find.byType(SnpChatResultCard)).height, lessThan(350));
    final originalJson = tester.widget<SelectableText>(apiText).data!;
    expect(copied, isNull);
    await tester.ensureVisible(find.text('複製 API JSON'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('複製 API JSON'));
    await tester.pumpAndSettle();
    final json = jsonDecode(copied!) as Map;
    expect(json['query'], '我能喝酒嗎');
    expect(json['topic'], '酒精');
    expect((json['variants'] as List).length, 77);
    expect(
        (json['variants'] as List)
            .map((e) => (e as String).split('-').first)
            .toSet()
            .length,
        77);
    await tester.ensureVisible(find.text('顯示 API JSON'));
    await tester.tap(find.text('顯示 API JSON'));
    await tester.pumpAndSettle();
    expect(apiText, findsNothing);
    expect(find.text('已完成，API JSON 已隱藏'), findsOneWidget);
    expect(p.runCalls, 1);
    expect(copied, originalJson);
    await tester.tap(find.text('顯示 API JSON'));
    await tester.pumpAndSettle();
    expect(tester.widget<SelectableText>(apiText).data, originalJson);
    expect(p.runCalls, 1);
    await tester.ensureVisible(find.text('查看 debug／分段計時'));
    await tester.tap(find.text('查看 debug／分段計時'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1163.000'), findsOneWidget);
    expect(chat.messages.map((m) => m.content), ['上一則對話']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), {'snp_chat_show_api_json'});
    expect(prefs.getBool('snp_chat_show_api_json'), true);
    p.stream.add(
        {'revision': 3, 'status': 'invalidated', 'errorCode': 'USB_REMOVED'});
    await tester.pumpAndSettle();
    expect(find.text('USB 診斷／分段計時'), findsNothing);
    expect(find.text('複製 API JSON'), findsNothing);
    expect(compute.locusResults, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    compute.dispose();
    chat.dispose();
    await p.stream.close();
  });
  testWidgets(
      'late set load cannot restore offline mode, and logout clears a running job',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final load = Completer<List<SnpQuery>>();
    final queries = SnpSets.alcohol
        .parse(File(SnpSets.alcohol.assetPath!).readAsBytesSync());
    final p = ChatUsbPlatform();
    final c = SnpComputeController(platform: p, supported: true);
    final chat = ChatController(api: NoAi(), threadId: 'loading');
    var loggedOut = false;
    await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider.value(
            value: chat,
            child: ChatRoomPage(
                snpCompute: c,
                snpSetLoader: (_) => load.future,
                onLogout: () {
                  loggedOut = true;
                }))));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
            .onPressed,
        isNull);
    p.sourceState = {
      'revision': 2,
      'sources': [],
      'volumes': [],
      'selectedSourceId': null
    };
    await c.refresh();
    load.complete(queries);
    await tester.pumpAndSettle();
    expect(find.text('複製 API JSON'), findsNothing);
    expect(p.runCalls, 0);
    p.sourceState = {
      ...p.sourceState,
      'revision': 3,
      'sources': [
        {'id': 'usb1', 'label': 'USB / gene'}
      ],
      'selectedSourceId': 'usb1'
    };
    await c.refresh();
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用此 USB'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '測試');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(c.busy, true);
    await tester.tap(find.byTooltip('開啟選單'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Log out'));
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    expect(loggedOut, true);
    expect(c.busy, false);
    expect(c.resultContext, isNull);
    expect(c.locusResults, isEmpty);
    expect(find.text('測試'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    chat.dispose();
    await p.stream.close();
  });
  testWidgets(
      'unsupported topic cannot submit offline; ordinary chat still uses original controller',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final p = ChatUsbPlatform();
    final c = SnpComputeController(platform: p, supported: true);
    final chat = ChatController(api: NoAi(), threadId: 'ordinary');
    await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider.value(
            value: chat, child: ChatRoomPage(snpCompute: c))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用此 USB'));
    await tester.pumpAndSettle();
    await chat.setTopic(ChatTopic.medication);
    await tester.pumpAndSettle();
    expect(find.textContaining('尚未提供 SNP set'), findsOneWidget);
    expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
            .onPressed,
        isNull);
    p.sourceState = {
      'revision': 2,
      'sources': [],
      'volumes': [],
      'selectedSourceId': null
    };
    await c.refresh();
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '一般聊天');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(chat.messages.any((m) => m.content == '一般聊天'), true);
    expect(p.runCalls, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    c.dispose();
    chat.dispose();
    await p.stream.close();
  });
  for (final readiness in ['permission', 'ambiguous', 'badPanel']) {
    testWidgets('USB $readiness blocks send without falling back',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final p = ChatUsbPlatform();
      if (readiness == 'permission') {
        p.sourceState = {
          'revision': 1,
          'sources': [],
          'volumes': [
            {'id': 'usb', 'label': 'USB', 'authorized': false}
          ],
          'selectedSourceId': null
        };
      } else if (readiness == 'ambiguous') {
        p.sourceState = {
          ...p.sourceState,
          'sources': [
            {'id': 'usb1', 'label': 'USB / one'},
            {'id': 'usb2', 'label': 'USB / two'}
          ],
          'selectedSourceId': null
        };
      }
      final c = SnpComputeController(platform: p, supported: true);
      final chat = ChatController(api: NoAi(), threadId: readiness);
      chat.geneLlmEnabled = true;
      await tester.pumpWidget(MaterialApp(
          home: ChangeNotifierProvider.value(
              value: chat,
              child: ChatRoomPage(
                  snpCompute: c,
                  snpSetLoader: (_) => readiness == 'badPanel'
                      ? Future.error(const FormatException('bad set'))
                      : Future.value(SnpSets.alcohol.parse(
                          File(SnpSets.alcohol.assetPath!)
                              .readAsBytesSync()))))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('USB 離線 SNP'), findsNothing);
      if (readiness == 'permission') {
        expect(find.textContaining('USB 待設定'), findsOneWidget);
        await tester.tap(find.byTooltip('開啟設定'));
        await tester.pumpAndSettle();
        expect(find.text('授權'), findsOneWidget);
        expect(p.runCalls, 0);
      }
      expect(
          tester
              .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
              .onPressed,
          isNull);
      if (readiness == 'badPanel') {
        expect(find.textContaining('SNP set 載入失敗'), findsOneWidget);
      }
      await tester.enterText(find.byType(TextField), '不應送至網路');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      expect(p.runCalls, 0);
      expect(chat.messages, isEmpty);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      chat.dispose();
      await p.stream.close();
    });
  }
  for (final interrupt in ['cancel', 'USB_REMOVED']) {
    testWidgets(
        'USB insertion waits for send; $interrupt rejects late completion',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final queries = SnpSets.alcohol
          .parse(File(SnpSets.alcohol.assetPath!).readAsBytesSync());
      final p = ChatUsbPlatform();
      final ready = p.sourceState;
      p.sourceState = {
        'revision': 1,
        'sources': [],
        'volumes': [],
        'selectedSourceId': null
      };
      final c = SnpComputeController(platform: p, supported: true);
      final chat = ChatController(api: NoAi(), threadId: interrupt);
      chat.geneLlmEnabled = true;
      await tester.pumpWidget(MaterialApp(
          home: ChangeNotifierProvider.value(
              value: chat,
              child: ChatRoomPage(
                  snpCompute: c, snpSetLoader: (_) => Future.value(queries)))));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('usb-source-icon')), findsNothing);
      p.sourceState = {...ready, 'revision': 2};
      await c.refresh();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('usb-source-icon')), findsOneWidget);
      expect(p.runCalls, 0);
      await tester.tap(find.text('使用此 USB'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '插入後才送出');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      expect(p.runCalls, 1);
      expect(p.lastDebug, false);
      expect(find.text('C 運算中：0／77 位點'), findsOneWidget);
      if (interrupt == 'cancel') {
        await tester.tap(find.text('取消離線計算'));
      } else {
        p.stream.add({
          'revision': 3,
          'status': 'invalidated',
          'errorCode': 'USB_REMOVED'
        });
      }
      p.stream.add({
        'jobId': 'job1',
        'revision': 4,
        'status': 'completed',
        'completed': 77,
        'total': 77,
        'mode': 'locus',
        'results': SnpLocus.group(queries).map(locusWire).toList()
      });
      await tester.pumpAndSettle();
      expect(find.text('複製 API JSON'), findsNothing);
      expect(c.locusResults, isEmpty);
      expect(chat.messages, isEmpty);
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      chat.dispose();
      await p.stream.close();
    });
  }
}
