import 'dart:io';

import 'package:connectly/features/auth/data/login_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  test('remembered email persists after closing and reopening Hive', () async {
    final directory = await Directory.systemTemp.createTemp('connectly_login_');
    Hive.init(directory.path);
    try {
      var box = await Hive.openBox<String>('auth_preferences_test');
      await HiveLoginPreferences(box).saveEmail('member@example.com');
      await box.close();

      box = await Hive.openBox<String>('auth_preferences_test');
      expect(HiveLoginPreferences(box).rememberedEmail, 'member@example.com');
      expect(box.keys.toList(), ['remembered_email']);
      await HiveLoginPreferences(box).saveEmail(null);
      await box.close();

      box = await Hive.openBox<String>('auth_preferences_test');
      expect(HiveLoginPreferences(box).rememberedEmail, isNull);
      await box.close();
    } finally {
      await Hive.close();
      final tempRoot = await Directory.systemTemp.resolveSymbolicLinks();
      final testPath = await directory.resolveSymbolicLinks();
      if (!testPath.startsWith(
        '$tempRoot${Platform.pathSeparator}connectly_login_',
      )) {
        throw StateError('Unexpected test directory; refusing cleanup.');
      }
      await directory.delete(recursive: true);
    }
  });
}
