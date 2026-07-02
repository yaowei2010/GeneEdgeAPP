import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:provider/provider.dart";

import "package:geneapp/api_service.dart";
import "package:geneapp/chat_controller.dart";
import "package:geneapp/chat_room_page.dart";
import "package:geneapp/main.dart";

void main() {
  testWidgets("renders login screen", (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text("GeneEdge"), findsOneWidget);
    expect(find.text("Welcome back"), findsOneWidget);
    expect(find.text("Continue without account"), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets("continues from login to splash", (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    await tester.tap(find.text("Continue without account"));
    await tester.pump();

    expect(find.text("Loading..."), findsOneWidget);
  });

  testWidgets("opens drawer and logs out", (WidgetTester tester) async {
    var loggedOut = false;
    final controller = ChatController(
      api: ApiServiceFake(),
      threadId: "test-thread",
      localMockPayload: const {
        "user_id": "test",
        "query": "test",
        "topic": "酒精",
        "SNP_list": [],
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider.value(
          value: controller,
          child: ChatRoomPage(
            onLogout: () => loggedOut = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();

    expect(find.text("Switch topic"), findsOneWidget);
    expect(find.text("Log out"), findsOneWidget);

    await tester.tap(find.text("Log out"));
    await tester.pumpAndSettle();

    expect(loggedOut, isTrue);
  });

  testWidgets("switches topic from the picker", (WidgetTester tester) async {
    final controller = ChatController(
      api: ApiServiceFake(),
      threadId: "test-thread",
      localMockPayload: const {
        "user_id": "test",
        "query": "test",
        "topic": "酒精",
        "SNP_list": [],
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider.value(
          value: controller,
          child: const ChatRoomPage(),
        ),
      ),
    );

    expect(find.text("酒精代謝"), findsWidgets);

    await tester.tap(find.byIcon(Icons.expand_more_rounded));
    await tester.pumpAndSettle();

    expect(find.text("選擇健康主題"), findsOneWidget);
    await tester.tap(find.text("藥物反應").last);
    await tester.pumpAndSettle();

    expect(find.text("藥物反應"), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets("empty state stays stable when keyboard opens", (tester) async {
    final controller = ChatController(
      api: ApiServiceFake(),
      threadId: "test-thread",
      localMockPayload: const {
        "user_id": "test",
        "query": "test",
        "topic": "酒精",
        "SNP_list": [],
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider.value(
          value: controller,
          child: const ChatRoomPage(),
        ),
      ),
    );

    await tester.showKeyboard(find.byType(TextField));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

class ApiServiceFake extends Fake implements ApiService {}
