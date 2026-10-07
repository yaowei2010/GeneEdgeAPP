import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geneapp/chat_controller.dart';
import 'package:geneapp/chat_room_page.dart';
import 'package:geneapp/models.dart';
import 'package:geneapp/snp_compute.dart';
import 'package:geneapp/snp_sets.dart';
import 'package:geneapp/snp_chat_panel.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'snp_chat_panel_test.dart' show ChatUsbPlatform;
import 'snp_locus_compute_test.dart' show locusWire;
import 'usb_llm_controller_test.dart' show UsbLlmApi;

void main() {
  final queries =
      SnpSets.alcohol.parse(File(SnpSets.alcohol.assetPath!).readAsBytesSync());
  late ChatUsbPlatform p;
  late SnpComputeController snp;
  late UsbLlmApi api;
  late ChatController chat;
  var revision = 1;
  setUp(() {
    SharedPreferences.setMockInitialValues({'snp_chat_show_api_json': false});
    p = ChatUsbPlatform();
    snp = SnpComputeController(platform: p, supported: true);
    api = UsbLlmApi();
    chat = ChatController(api: api, threadId: 'usb-llm', llmUserId: 'u1');
    chat.geneLlmEnabled = true;
    revision = 1;
  });
  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider.value(
            value: chat,
            child: ChatRoomPage(
                snpCompute: snp,
                snpSetLoader: (_) async => queries,
                onLogout: () {}))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用此 USB'));
    await tester.pumpAndSettle();
  }

  Future<void> send(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), '我能喝酒嗎');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
  }

  Future<void> complete(WidgetTester tester) async {
    final loci = SnpLocus.group(queries);
    p.stream.add({
      'revision': ++revision,
      'jobId': 'job1',
      'status': 'completed',
      'mode': 'locus',
      'completed': 77,
      'total': 77,
      'results': List.generate(77, (i) => locusWire(loci[i], noCall: i >= 70))
    });
    await tester.pump();
    await tester.pump();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    snp.dispose();
    chat.dispose();
  }

  testWidgets(
      'upper USB GeneLLM shares drawer state and original preference without running',
      (tester) async {
    chat.geneLlmEnabled = false;
    await mount(tester);
    await tester.tap(find.byTooltip('開啟設定'));
    await tester.pumpAndSettle();
    final control = find.byKey(const ValueKey('usb-gene-llm-switch'));
    expect(control, findsOneWidget);
    expect(tester.widget<SwitchListTile>(control).value, false);
    expect(find.textContaining('LLM OFF：'), findsOneWidget);
    await tester.tap(control);
    await tester.pumpAndSettle();
    expect(chat.geneLlmEnabled, true);
    expect(find.textContaining('LLM ON：'), findsOneWidget);
    expect(p.runCalls, 0);
    expect(api.requests, isEmpty);
    await tester.tap(find.byTooltip('開啟選單'));
    await tester.pumpAndSettle();
    expect(find.text('GeneLLM on'), findsOneWidget);
    await tester.tap(find.text('GeneLLM on'));
    await tester.pumpAndSettle();
    expect(find.text('GeneLLM off'), findsOneWidget);
    final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold).first);
    scaffold.closeDrawer();
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(control).value, false);
    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString('chat_thread_usb-llm')!) as Map;
    expect(saved['gene_llm_enabled'], false);
    final restored = ChatController(api: api, threadId: 'usb-llm');
    await restored.load();
    expect(restored.geneLlmEnabled, false);
    restored.dispose();
    expect(prefs.getKeys(), {'chat_thread_usb-llm', 'snp_chat_show_api_json'});
    expect(p.runCalls, 0);
    expect(api.requests, isEmpty);
    await tester.tap(control);
    await tester.pumpAndSettle();
    await send(tester);
    expect(tester.widget<SwitchListTile>(control).onChanged, isNull);
    await complete(tester);
    expect(api.requests.length, 1);
    expect(tester.widget<SwitchListTile>(control).onChanged, isNull);
    api.answer(0, '開關測試回覆');
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(control).onChanged, isNotNull);
    await dispose(tester);
  });
  testWidgets(
      'enabling upper USB GeneLLM never retroactively sends completed offline JSON',
      (tester) async {
    chat.geneLlmEnabled = false;
    await mount(tester);
    await send(tester);
    await complete(tester);
    await tester.tap(find.byTooltip('開啟設定'));
    await tester.pumpAndSettle();
    final control = find.byKey(const ValueKey('usb-gene-llm-switch'));
    expect(control, findsOneWidget);
    await tester.tap(control);
    await tester.pumpAndSettle();
    expect(chat.geneLlmEnabled, true);
    expect(api.requests, isEmpty);
    expect(p.runCalls, 1);
    expect(snp.status, 'completed');
    await dispose(tester);
  });
  testWidgets(
      'USB form GeneLLM remains bounded with keyboard and busy JSON switch is independent',
      (tester) async {
    await mount(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    addTearDown(tester.view.resetViewInsets);
    await tester.tap(find.byTooltip('開啟設定'));
    await tester.pumpAndSettle();
    final control = find.byKey(const ValueKey('usb-gene-llm-switch'));
    expect(control, findsOneWidget);
    expect(control.hitTestable(), findsOneWidget);
    await send(tester);
    expect(tester.widget<SwitchListTile>(control).onChanged, isNull);
    expect(
        tester
            .widget<SwitchListTile>(
                find.widgetWithText(SwitchListTile, '顯示 API JSON'))
            .onChanged,
        isNotNull);
    await complete(tester);
    expect(tester.widget<SwitchListTile>(control).onChanged, isNull);
    expect(tester.takeException(), isNull);
    api.answer(0, 'bounded reply');
    await tester.pumpAndSettle();
    await dispose(tester);
  });
  testWidgets('GeneLLM switch without actionable callback is disabled',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: SnpChatControls(
                    controller: snp,
                    set: SnpSets.alcohol,
                    queries: queries,
                    error: null,
                    showApiJson: false,
                    onShowApiJsonChanged: (_) {},
                    onOpenDiagnostics: () {},
                    geneLlmEnabled: true)))));
    final control = find.byKey(const ValueKey('usb-gene-llm-switch'));
    expect(control, findsOneWidget);
    expect(tester.widget<SwitchListTile>(control).value, true);
    expect(tester.widget<SwitchListTile>(control).onChanged, isNull);
    await dispose(tester);
  });
  testWidgets(
      'enabled snapshot survives toggle off; visibility changes never resend or hide answer',
      (tester) async {
    await mount(tester);
    await send(tester);
    await chat.setGeneLlmEnabled(false);
    await complete(tester);
    expect(api.requests.length, 1);
    await tester.tap(find.byTooltip('開啟設定'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('顯示 API JSON'));
    await tester.tap(find.text('顯示 API JSON'));
    await tester.pumpAndSettle();
    expect(api.requests.length, 1);
    expect(p.runCalls, 1);
    final debug = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Debug：結果與分段計時'));
    expect(debug.onChanged, isNull);
    api.answer(0, '回覆不受 JSON 隱藏影響');
    await tester.pumpAndSettle();
    await tester.tap(find.text('顯示 API JSON'));
    await tester.pumpAndSettle();
    expect(find.text('回覆不受 JSON 隱藏影響'), findsOneWidget);
    expect(api.requests.length, 1);
    await dispose(tester);
  });
  testWidgets('old request finally cannot clear waiting state of a newer job',
      (tester) async {
    await mount(tester);
    await send(tester);
    await complete(tester);
    await snp.cancel();
    await tester.pumpAndSettle();
    await send(tester);
    await complete(tester);
    expect(api.requests.length, 2);
    api.answer(0, '過期回覆');
    await tester.pumpAndSettle();
    expect(find.text('過期回覆'), findsNothing);
    expect(find.text('等待 LLM 回覆…'), findsOneWidget);
    expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
            .onPressed,
        isNull);
    api.answer(1, '新回覆');
    await tester.pumpAndSettle();
    expect(find.text('新回覆'), findsOneWidget);
    await dispose(tester);
  });
  testWidgets(
      'GeneLLM off blocks retry, re-enabling does not automatically retry',
      (tester) async {
    await mount(tester);
    await send(tester);
    await complete(tester);
    api.replies.single.completeError(Exception('offline'));
    await tester.pumpAndSettle();
    await chat.setGeneLlmEnabled(false);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '重試 LLM'))
            .onPressed,
        isNull);
    await chat.setGeneLlmEnabled(true);
    await tester.pumpAndSettle();
    expect(api.requests.length, 1);
    await dispose(tester);
  });
  for (final terminal in ['cancel', 'error', 'partial', 'invalid']) {
    testWidgets('enabled submission never sends $terminal computation',
        (tester) async {
      await mount(tester);
      await send(tester);
      if (terminal == 'cancel') {
        await snp.cancel();
      } else {
        p.stream.add({
          'revision': ++revision,
          'jobId': 'job1',
          'status': terminal == 'error'
              ? 'error'
              : terminal == 'partial'
                  ? 'running'
                  : 'completed',
          'mode': 'locus',
          'completed': 1,
          'total': 77,
          'errorCode': terminal == 'error' ? 'IO_ERROR' : null,
          if (terminal == 'invalid')
            'results': [locusWire(SnpLocus.group(queries).first)]
        });
      }
      await tester.pumpAndSettle();
      expect(api.requests, isEmpty);
      await dispose(tester);
    });
  }
  testWidgets(
      'enabled USB completion sends once with hidden JSON and shows existing chat answer',
      (tester) async {
    await mount(tester);
    await send(tester);
    expect(api.requests, isEmpty);
    await complete(tester);
    expect(api.requests.length, 1);
    expect(api.requests.single['variant_input_count'], 77);
    expect(api.requests.single['no_call_count'], 7);
    expect((api.requests.single['variants'] as List).length, 70);
    expect(find.text('等待 LLM 回覆…'), findsOneWidget);
    expect(find.text('已完成，API JSON 已隱藏'), findsOneWidget);
    final sendButton =
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send));
    expect(sendButton.onPressed, isNull);
    await complete(tester);
    expect(api.requests.length, 1);
    api.answer(0, '測試回覆');
    await tester.pumpAndSettle();
    expect(find.text('測試回覆'), findsOneWidget);
    expect(chat.messages, isEmpty);
    expect((await SharedPreferences.getInstance()).getKeys(),
        {'snp_chat_show_api_json'});
    await dispose(tester);
  });
  testWidgets(
      'GeneLLM flag is captured at send, off stays offline after toggle',
      (tester) async {
    chat.geneLlmEnabled = false;
    await mount(tester);
    await send(tester);
    await chat.setGeneLlmEnabled(true);
    await complete(tester);
    expect(api.requests, isEmpty);
    expect(find.text('已完成，API JSON 已隱藏'), findsOneWidget);
    await dispose(tester);
  });
  testWidgets(
      'HTTP error stays safe and explicit retry reuses completed C result',
      (tester) async {
    await mount(tester);
    await send(tester);
    await complete(tester);
    expect(api.requests.length, 1);
    api.replies.single
        .completeError(Exception('HTTP 500 private genotype body'));
    await tester.pumpAndSettle();
    expect(find.textContaining('LLM 回覆失敗'), findsOneWidget);
    expect(find.textContaining('private genotype'), findsNothing);
    await tester.ensureVisible(find.text('重試 LLM'));
    await tester.tap(find.text('重試 LLM'));
    await tester.pump();
    expect(api.requests.length, 2);
    expect(api.requests[1], api.requests[0]);
    expect(p.runCalls, 1);
    api.answer(1, '測試回覆');
    await tester.pumpAndSettle();
    expect(find.text('測試回覆'), findsOneWidget);
    expect(find.text('重試 LLM'), findsNothing);
    expect(chat.messages, isEmpty);
    await dispose(tester);
  });
  for (final invalidation in [
    'remove',
    'topic',
    'cancel',
    'source',
    'logout',
    'dispose'
  ]) {
    for (final failure in [false, true]) {
      testWidgets(
          'late ${failure ? 'failure' : 'answer'} ignored after $invalidation',
          (tester) async {
        await mount(tester);
        await send(tester);
        await complete(tester);
        expect(api.requests.length, 1);
        switch (invalidation) {
          case 'remove':
            p.stream.add({
              'revision': ++revision,
              'status': 'invalidated',
              'errorCode': 'USB_REMOVED'
            });
          case 'topic':
            await chat.setTopic(ChatTopic.medication);
          case 'cancel':
            await snp.cancel();
          case 'source':
            await snp.selectSource('usb1');
          case 'dispose':
            await tester.pumpWidget(const SizedBox());
          case 'logout':
            await tester.tap(find.byTooltip('開啟選單'));
            await tester.pumpAndSettle();
            await tester.ensureVisible(find.text('Log out'));
            await tester.tap(find.text('Log out'));
        }
        await tester.pump();
        if (failure) {
          api.replies.single.completeError(Exception('private late error'));
        } else {
          api.answer(0, '過期回覆');
        }
        await tester.pumpAndSettle();
        expect(find.text('過期回覆'), findsNothing);
        expect(find.textContaining('LLM 回覆失敗'), findsNothing);
        expect(find.text('重試 LLM'), findsNothing);
        expect(chat.messages.where((m) => m.role != Role.system), isEmpty);
        await dispose(tester);
      });
    }
  }
}
