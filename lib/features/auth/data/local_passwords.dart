import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';

class LocalPasswords {
  LocalPasswords({this.iterations = 120000});
  final int iterations;

  Future<String> hash(String password) async {
    final random = Random.secure();
    final salt = List.generate(16, (_) => random.nextInt(256));
    final key = await Pbkdf2(
            macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256)
        .deriveKeyFromPassword(password: password, nonce: salt);
    return 'pbkdf2_sha256\$$iterations\$${base64Encode(salt)}\$${base64Encode(await key.extractBytes())}';
  }

  Future<bool> verify(String password, String stored) async {
    try {
      final parts = stored.split(r'$');
      if (parts.length != 4 || parts[0] != 'pbkdf2_sha256') return false;
      final rounds = int.parse(parts[1]);
      if (rounds < 1 || rounds > 1000000) return false;
      final salt = base64Decode(parts[2]);
      final expected = base64Decode(parts[3]);
      if (salt.length != 16 || expected.length != 32) return false;
      final derived = await Pbkdf2(
              macAlgorithm: Hmac.sha256(), iterations: rounds, bits: 256)
          .deriveKeyFromPassword(password: password, nonce: salt);
      final actual = await derived.extractBytes();
      var difference = 0;
      for (var i = 0; i < expected.length; i++) {
        difference |= expected[i] ^ actual[i];
      }
      return difference == 0;
    } on FormatException {
      return false;
    }
  }
}
