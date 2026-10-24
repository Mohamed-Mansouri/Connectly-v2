import 'dart:async';

import 'package:connectly/app/connectly_app.dart';
import 'package:connectly/app/connectly_theme.dart';
import 'package:connectly/features/auth/data/login_preferences.dart';
import 'package:connectly/features/auth/presentation/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryLoginPreferences implements LoginPreferences {
  MemoryLoginPreferences([this.email]);

  String? email;

  @override
  String? get rememberedEmail => email;

  @override
  Future<void> saveEmail(String? email) async {
    this.email = email;
  }
}

Future<void> pumpLogin(
  WidgetTester tester, {
  LoginPreferences? preferences,
  Future<void> Function(String, String)? onSignIn,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ConnectlyTheme.dark,
      home: LoginScreen(
        preferences: preferences ?? MemoryLoginPreferences(),
        onContinueAsGuest: () {},
        onSignIn: onSignIn,
      ),
    ),
  );
}

Future<void> tapSubmit(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('login_submit')));
  await tester.tap(find.byKey(const Key('login_submit')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('requires valid email and a password before submitting',
      (tester) async {
    var calls = 0;
    await pumpLogin(tester, onSignIn: (_, __) async {
      calls++;
    });
    await tapSubmit(tester);
    expect(find.text('Enter your email address.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
    expect(calls, 0);

    await tester.enterText(find.byKey(const Key('login_email')), 'invalid');
    await tapSubmit(tester);
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('restores the email and immediately clears it when unchecked',
      (tester) async {
    final preferences = MemoryLoginPreferences('member@example.com');
    await pumpLogin(tester, preferences: preferences);
    expect(find.text('member@example.com'), findsOneWidget);
    final password = tester.widget<TextFormField>(
      find.byKey(const Key('login_password')),
    );
    expect(password.controller!.text, isEmpty);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(preferences.email, isNull);
  });

  testWidgets('shows and hides the password', (tester) async {
    await pumpLogin(tester);
    expect(
      tester
          .widget<TextField>(find.descendant(
            of: find.byKey(const Key('login_password')),
            matching: find.byType(TextField),
          ))
          .obscureText,
      isTrue,
    );
    await tester.ensureVisible(find.byTooltip('Show password'));
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.descendant(
            of: find.byKey(const Key('login_password')),
            matching: find.byType(TextField),
          ))
          .obscureText,
      isFalse,
    );
  });

  testWidgets('normalizes email, blocks duplicate submits and handles failure',
      (tester) async {
    final pending = Completer<void>();
    var calls = 0;
    await pumpLogin(tester, onSignIn: (email, password) {
      expect(email, 'member@example.com');
      expect(password, ' pass with spaces ');
      calls++;
      return pending.future;
    });
    await tester.enterText(
      find.byKey(const Key('login_email')),
      ' member@example.com ',
    );
    await tester.enterText(
      find.byKey(const Key('login_password')),
      ' pass with spaces ',
    );
    await tester.ensureVisible(find.byKey(const Key('login_submit')));
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pump();
    expect(calls, 1);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('login_submit')))
          .onPressed,
      isNull,
    );
    pending.completeError(StateError('Service unavailable'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Check your details and try again.'),
        findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('login_submit')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('guest opens module tabs directly without a welcome screen',
      (tester) async {
    await tester.pumpWidget(
      ConnectlyApp(loginPreferences: MemoryLoginPreferences()),
    );
    await tester.ensureVisible(find.byKey(const Key('login_guest')));
    await tester.tap(find.byKey(const Key('login_guest')));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Welcome to Connectly'), findsNothing);
    expect(find.text('Open modules'), findsNothing);
  });

  testWidgets('fits a small screen with a keyboard and enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        theme: ConnectlyTheme.dark,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            viewInsets: EdgeInsets.only(bottom: 240),
            textScaler: TextScaler.linear(1.4),
          ),
          child: LoginScreen(
            preferences: MemoryLoginPreferences(),
            onContinueAsGuest: () {},
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('login_submit')).hitTestable(), findsOneWidget);
  });

  testWidgets('guest action stays above the system navigation area',
      (tester) async {
    tester.view.physicalSize = const Size(392, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ConnectlyTheme.dark,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(392, 800),
            padding: EdgeInsets.only(bottom: 48),
            viewPadding: EdgeInsets.only(bottom: 48),
          ),
          child: LoginScreen(
            preferences: MemoryLoginPreferences(),
            onContinueAsGuest: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final guest = find.byKey(const Key('login_guest'));
    expect(guest.hitTestable(), findsOneWidget);
    expect(tester.getRect(guest).bottom, lessThanOrEqualTo(752));
    expect(tester.takeException(), isNull);
  });
}
