import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geneapp/api_service.dart';
import 'package:geneapp/bluemagpie_poc_availability.dart';
import 'package:geneapp/chat_controller.dart';
import 'package:geneapp/chat_room_page.dart';
import 'package:provider/provider.dart';

void main() {
  test('developer entry requires flag, debug mode, Android, and ARM64 probe', () {
    expect(
      BlueMagpiePocAvailability.canShowEntry(
        featureEnabled: true,
        debugMode: true,
        platform: TargetPlatform.android,
        isArm64: true,
      ),
      isTrue,
    );

    for (final unsupported in <BlueMagpiePocAvailabilityCase>[
      const BlueMagpiePocAvailabilityCase(featureEnabled: false),
      const BlueMagpiePocAvailabilityCase(debugMode: false),
      const BlueMagpiePocAvailabilityCase(platform: TargetPlatform.iOS),
      const BlueMagpiePocAvailabilityCase(isArm64: false),
    ]) {
      expect(
        BlueMagpiePocAvailability.canShowEntry(
          featureEnabled: unsupported.featureEnabled,
          debugMode: unsupported.debugMode,
          platform: unsupported.platform,
          isArm64: unsupported.isArm64,
        ),
        isFalse,
      );
    }
  });

  testWidgets('drawer omits BlueMagpie entry when PoC is unavailable',
      (tester) async {
    await tester.pumpWidget(_chatApp());

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();

    expect(find.text('藍鵲 TTS 測試'), findsNothing);
  });

  testWidgets('drawer opens developer-only BlueMagpie page when enabled',
      (tester) async {
    var opened = false;
    await tester.pumpWidget(_chatApp(onOpenBlueMagpiePoc: () => opened = true));

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('藍鵲 TTS 測試'));

    expect(opened, isTrue);
  });
}

Widget _chatApp({VoidCallback? onOpenBlueMagpiePoc}) {
  final controller = ChatController(
    api: _FakeApiService(),
    threadId: 'bluemagpie-navigation-test',
    localMockPayload: const {
      'user_id': 'test',
      'query': 'test',
      'topic': '酒精',
      'SNP_list': <Object>[],
    },
  );
  return MaterialApp(
    home: ChangeNotifierProvider.value(
      value: controller,
      child: ChatRoomPage(onOpenBlueMagpiePoc: onOpenBlueMagpiePoc),
    ),
  );
}

class _FakeApiService extends Fake implements ApiService {}

class BlueMagpiePocAvailabilityCase {
  const BlueMagpiePocAvailabilityCase({
    this.featureEnabled = true,
    this.debugMode = true,
    this.platform = TargetPlatform.android,
    this.isArm64 = true,
  });

  final bool featureEnabled;
  final bool debugMode;
  final TargetPlatform platform;
  final bool isArm64;
}
