import 'package:connectly/app/connectly_app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home opens all module tabs and back returns home', (tester) async {
    await tester.pumpWidget(const ConnectlyApp());

    expect(find.text('Welcome to Connectly'), findsOneWidget);
    await tester.tap(find.text('Open modules'));
    await tester.pumpAndSettle();
    expect(find.text('Feed module'), findsOneWidget);

    await tester.tap(find.text('Nearby'));
    await tester.pumpAndSettle();
    expect(find.text('Nearby module'), findsOneWidget);

    await tester.tap(find.text('Chats'));
    await tester.pumpAndSettle();
    expect(find.text('Chats module'), findsOneWidget);

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Profile module'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Connectly'), findsOneWidget);
  });
}
