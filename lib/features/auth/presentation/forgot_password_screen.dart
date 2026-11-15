import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/connectly_theme.dart';
import '../domain/auth_models.dart';

/// Two steps: email a 6-digit code, then exchange it for a new password.
/// Pops with the account email after a successful reset.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen(
      {required this.onRequestCode,
      required this.onReset,
      this.initialEmail = '',
      super.key});
  final Future<void> Function(String email) onRequestCode;
  final Future<void> Function(String email, String code, String password)
      onReset;
  final String initialEmail;
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  bool _hidePassword = true;
  String? _message;
  int _resendIn = 0;
  Timer? _timer;
  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _resendIn = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _resendIn <= 1) {
        timer.cancel();
        if (mounted) setState(() => _resendIn = 0);
        return;
      }
      setState(() => _resendIn--);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on AuthException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() async {
    final email = _email.text.trim();
    if (!_emailPattern.hasMatch(email)) {
      setState(() => _message = 'Enter a valid email address.');
      return;
    }
    await _run(() async {
      await widget.onRequestCode(email);
      if (!mounted) return;
      _code.clear();
      setState(() {
        _codeSent = true;
        _message = 'We sent a 6-digit code to $email. '
            'Check your inbox and spam folder.';
      });
      _startCooldown();
    });
  }

  Future<void> _reset() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _email.text.trim();
    await _run(() async {
      await widget.onReset(email, _code.text.trim(), _password.text);
      if (mounted) Navigator.of(context).pop(email);
    });
  }

  InputDecoration _decoration(String hint, IconData icon) => InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 21),
        filled: true,
        fillColor: ConnectlyTheme.navy,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        errorMaxLines: 2,
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Reset password')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                // Not a lazy ListView: every field must be built to validate.
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                          _codeSent
                              ? 'Enter the code and a new password'
                              : 'Forgot your password?',
                          style: const TextStyle(
                              fontFamily: 'Urbanist',
                              fontSize: 26,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(
                          _codeSent
                              ? 'The code expires in 15 minutes.'
                              : "Enter your account's email and we'll send you a code to set a new password.",
                          style: const TextStyle(
                              color: Color(0xFFB8C5DA), height: 1.5)),
                      const SizedBox(height: 24),
                      TextField(
                        key: const Key('reset_email'),
                        controller: _email,
                        enabled: !_busy && !_codeSent,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _sendCode(),
                        decoration:
                            _decoration('you@example.com', Icons.mail_outline),
                      ),
                      if (_codeSent) ...[
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => setState(() {
                                        _codeSent = false;
                                        _message = null;
                                      }),
                              child: const Text('Use a different email')),
                        ),
                        TextFormField(
                          key: const Key('reset_code'),
                          controller: _code,
                          enabled: !_busy,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          autofillHints: const [AutofillHints.oneTimeCode],
                          decoration: _decoration('6-digit code', Icons.pin)
                              .copyWith(counterText: ''),
                          validator: (v) =>
                              RegExp(r'^\d{6}$').hasMatch(v?.trim() ?? '')
                                  ? null
                                  : 'Enter the 6-digit code from the email.',
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          key: const Key('reset_password'),
                          controller: _password,
                          enabled: !_busy,
                          obscureText: _hidePassword,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: _decoration(
                                  'New password', Icons.lock_outline)
                              .copyWith(
                                  suffixIcon: IconButton(
                                      tooltip: _hidePassword
                                          ? 'Show password'
                                          : 'Hide password',
                                      onPressed: () => setState(
                                          () => _hidePassword = !_hidePassword),
                                      icon: Icon(_hidePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined))),
                          validator: (v) =>
                              (v?.length ?? 0) < 8 || (v?.length ?? 0) > 128
                                  ? 'Use 8–128 characters.'
                                  : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          key: const Key('reset_confirm'),
                          controller: _confirm,
                          enabled: !_busy,
                          obscureText: _hidePassword,
                          decoration: _decoration(
                              'Confirm new password', Icons.lock_outline),
                          validator: (v) => v != _password.text
                              ? 'Passwords do not match.'
                              : null,
                        ),
                      ],
                      if (_message != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Semantics(
                            liveRegion: true,
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                  color: ConnectlyTheme.navy,
                                  borderRadius: BorderRadius.circular(12)),
                              child: Text(_message!),
                            ),
                          ),
                        ),
                      const SizedBox(height: 22),
                      FilledButton(
                        key: Key(_codeSent ? 'reset_submit' : 'reset_send'),
                        onPressed:
                            _busy ? null : (_codeSent ? _reset : _sendCode),
                        style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(54)),
                        child: _busy
                            ? const SizedBox.square(
                                dimension: 22,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : Text(
                                _codeSent ? 'Set new password' : 'Send code'),
                      ),
                      if (_codeSent)
                        TextButton(
                          key: const Key('reset_resend'),
                          onPressed: _busy || _resendIn > 0 ? null : _sendCode,
                          child: Text(_resendIn > 0
                              ? 'Resend code in ${_resendIn}s'
                              : 'Resend code'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
