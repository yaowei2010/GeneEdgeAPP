import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geneapp/api_service.dart';
import 'package:geneapp/chat_controller.dart';
import 'package:geneapp/chat_room_page.dart';
import 'package:geneapp/snp_compute.dart';
import 'package:geneapp/snp_compute_page.dart';
import 'package:geneapp/usb_gene_dongle.dart';
import 'package:provider/provider.dart';

// Unexpected API calls throw through Fake.noSuchMethod, never return mock AI.
class _NoAiCalls extends Fake implements ApiService {}

void main() {
  testWidgets('Android drawer opens independent C compute route without AI',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final chat = ChatController(api: _NoAiCalls(), threadId: 'snp-navigation');
    final usb = UsbGeneDongleController(supported: false);
    final methods = <String>[];
    var listens = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(MethodChannelSnpComputePlatform.methods,
        (call) async {
      methods.add(call.method);
      if (call.method != 'sources') {
        throw StateError('Navigation must not start computation');
      }
      return {
        'revision': 0,
        'sources': <Object?>[],
        'volumes': <Object?>[],
        'selectedSourceId': null,
      };
    });
    const events = MethodChannel('geneedge/snp_compute/events');
    messenger.setMockMethodCallHandler(events, (call) async {
      if (call.method == 'listen') listens++;
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(
          MethodChannelSnpComputePlatform.methods, null);
      messenger.setMockMethodCallHandler(events, null);
      chat.dispose();
      usb.dispose();
    });
    await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider.value(
            value: chat, child: ChatRoomPage(usbGeneDongle: usb))));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('手機 SNP 運算'));
    await tester.tap(find.text('手機 SNP 運算'));
    await tester.pumpAndSettle();
    expect(find.byType(SnpComputePage), findsOneWidget);
    expect(find.text('USB 離線 SNP 運算'), findsOneWidget);
    expect(find.textContaining('未校準'), findsOneWidget);
    expect(methods, ['sources']);
    expect(listens, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('non Android drawer omits native compute entry', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final chat = ChatController(api: _NoAiCalls(), threadId: 'snp-non-android');
    final usb = UsbGeneDongleController(supported: false);
    addTearDown(() {
      chat.dispose();
      usb.dispose();
    });
    await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider.value(
            value: chat, child: ChatRoomPage(usbGeneDongle: usb))));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();
    expect(find.text('手機 SNP 運算'), findsNothing);
    expect(find.byType(SnpComputePage), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });
}
