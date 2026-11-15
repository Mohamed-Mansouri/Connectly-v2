import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

import '../domain/auth_models.dart';

/// Delivers password-reset codes to an account's email address.
abstract class PasswordResetMailer {
  bool get configured;
  Future<void> sendCode({required String to, required String code});
}

/// Sends through Gmail SMTP with an App Password supplied at build time:
/// `flutter run --dart-define-from-file=email_secrets.json`
/// (see `email_secrets.example.json`). Nothing is stored in source control.
class GmailPasswordResetMailer implements PasswordResetMailer {
  const GmailPasswordResetMailer({
    this.user = const String.fromEnvironment('SMTP_USER'),
    this.password = const String.fromEnvironment('SMTP_PASSWORD'),
  });

  final String user;
  final String password;

  @override
  bool get configured => user.isNotEmpty && password.isNotEmpty;

  @override
  Future<void> sendCode({required String to, required String code}) async {
    if (!configured) {
      throw const AuthException(
          'Password reset email is not set up in this build.');
    }
    final message = Message()
      ..from = Address(user, 'Connectly')
      ..recipients.add(to)
      ..subject = 'Your Connectly reset code: $code'
      ..text = 'Your Connectly password reset code is $code.\n\n'
          'It expires in 15 minutes. If you did not ask to reset your '
          'password, you can ignore this email.'
      ..html = '''
<div style="font-family:Arial,sans-serif;max-width:420px">
  <h2 style="margin:0 0 12px">Reset your Connectly password</h2>
  <p>Enter this code in the app:</p>
  <p style="font-size:32px;font-weight:bold;letter-spacing:6px;margin:16px 0">$code</p>
  <p style="color:#666">It expires in 15 minutes. If you did not ask to reset
  your password, you can ignore this email.</p>
</div>''';
    try {
      await send(message, gmail(user, password),
          timeout: const Duration(seconds: 20));
    } on MailerException {
      throw const AuthException(
          'The email could not be sent. Check the email address and try again.');
    } catch (_) {
      throw const AuthException(
          'The email could not be sent. Check your internet connection.');
    }
  }
}
