import "package:flutter_test/flutter_test.dart";

import "package:geneapp/main.dart";

void main() {
  testWidgets("renders splash screen", (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text("GeneEdgeRobot"), findsOneWidget);
    expect(find.text("Loading..."), findsOneWidget);
  });
}
