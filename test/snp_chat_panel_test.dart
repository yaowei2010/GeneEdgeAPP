import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geneapp/api_service.dart';
import 'package:geneapp/chat_controller.dart';
import 'package:geneapp/chat_room_page.dart';
import 'package:geneapp/models.dart';
import 'package:geneapp/snp_compute.dart';
import 'package:geneapp/snp_compute_page.dart';
import 'package:geneapp/snp_sets.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'snp_locus_compute_test.dart' show FakeLocusPlatform, locusWire;

class NoAi extends Fake implements ApiService {}

class ChatUsbPlatform extends FakeLocusPlatform {
  Map<String, Object?> sourceState = {
    'revision': 1,
    'sources': [
      {'id': 'usb1', 'label': 'USB / gene'}
    ],
    'volumes': [],
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
    await tester.tap(find.text('USB・手機 C'));
    await tester.pumpAndSettle();
    expect(find.textContaining('77 位點'), findsWidgets);
    expect(find.byType(SnpComputePage), findsNothing);
    await tester.ensureVisible(find.text('Debug：結果與分段計時'));
    await tester.tap(find.text('Debug：結果與分段計時'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '我能喝酒嗎');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(p.lastQueries.length, 143);
    expect(p.lastDebug, true);
    expect(
        tester
            .widget<AbsorbPointer>(find.byWidgetPredicate((w) =>
                w is AbsorbPointer &&
                w.child.runtimeType.toString() == '_ExperiencePanel'))
            .absorbing,
        true);
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
    expect(find.textContaining('1163.000'), findsOneWidget);
    expect(chat.messages.map((m) => m.content), ['上一則對話']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
    p.stream.add(
        {'revision': 3, 'status': 'invalidated', 'errorCode': 'USB_REMOVED'});
    await tester.pumpAndSettle();
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
      expect(find.text('USB 離線 SNP'), findsNothing);
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
      expect(find.text('USB・手機 C'), findsNothing);
      p.sourceState = {...ready, 'revision': 2};
      await c.refresh();
      await tester.pumpAndSettle();
      expect(find.text('USB・手機 C'), findsOneWidget);
      expect(p.runCalls, 0);
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
