import 'package:hive_flutter/hive_flutter.dart';

abstract class LoginPreferences {
  String? get rememberedEmail;

  Future<void> saveEmail(String? email);
}

class HiveLoginPreferences implements LoginPreferences {
  HiveLoginPreferences(this._box);

  final Box<String> _box;

  static Future<HiveLoginPreferences> open() async {
    await Hive.initFlutter();
    return HiveLoginPreferences(
      await Hive.openBox<String>('auth_preferences'),
    );
  }

  @override
  String? get rememberedEmail => _box.get('remembered_email');

  @override
  Future<void> saveEmail(String? email) async {
    if (email == null || email.isEmpty) {
      await _box.delete('remembered_email');
    } else {
      await _box.put('remembered_email', email);
    }
  }
}
