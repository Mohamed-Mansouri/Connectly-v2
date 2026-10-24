import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/connectly_theme.dart';
import '../domain/auth_models.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({required this.onSignUp, super.key});

  final Future<void> Function(String name, String email, String password)
      onSignUp;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void dispose() {
    for (final controller in [_name, _email, _password, _confirmation]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSignUp(
          _name.text.trim(), _email.text.trim(), _password.text);
      TextInput.finishAutofillContext();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'We couldn\'t create your account. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _decoration(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: ConnectlyTheme.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Create account')),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: AutofillGroup(
                  onDisposeAction: AutofillContextAction.cancel,
                  child: Form(
                    key: _formKey,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Find your people.',
                            style: TextStyle(
                              fontFamily: 'Urbanist',
                              fontSize: 36,
                              fontWeight: FontWeight.w700,
                            )),
                        const SizedBox(height: 8),
                        const Text('A new connection starts with you.',
                            style: TextStyle(
                              color: Color(0xFFB8C5DA),
                              fontSize: 16,
                            )),
                        const SizedBox(height: 28),
                        TextFormField(
                          key: const Key('signup_name'),
                          controller: _name,
                          enabled: !_busy,
                          autofillHints: const [AutofillHints.name],
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          decoration:
                              _decoration('Your name', Icons.person_outline),
                          validator: (value) {
                            final name = value?.trim() ?? '';
                            return name.length < 2 || name.length > 80
                                ? 'Use a name with 2 to 80 characters.'
                                : null;
                          },
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          key: const Key('signup_email'),
                          controller: _email,
                          enabled: !_busy,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                          autocorrect: false,
                          decoration:
                              _decoration('Email address', Icons.mail_outline),
                          validator: (value) {
                            final email = value?.trim() ?? '';
                            return email.length > 254 ||
                                    !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                        .hasMatch(email)
                                ? 'Enter a valid email address.'
                                : null;
                          },
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          key: const Key('signup_password'),
                          controller: _password,
                          enabled: !_busy,
                          obscureText: _hidePassword,
                          autofillHints: const [AutofillHints.newPassword],
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration:
                              _decoration('Password', Icons.lock_outline)
                                  .copyWith(
                            helperText: 'Use at least 8 characters.',
                            suffixIcon: IconButton(
                              tooltip: _hidePassword
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: _busy
                                  ? null
                                  : () => setState(
                                      () => _hidePassword = !_hidePassword),
                              icon: Icon(_hidePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                            ),
                          ),
                          validator: (value) => (value?.length ?? 0) < 8 ||
                                  (value?.length ?? 0) > 128
                              ? 'Use a password with 8 to 128 characters.'
                              : null,
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          key: const Key('signup_confirmation'),
                          controller: _confirmation,
                          enabled: !_busy,
                          obscureText: _hidePassword,
                          textInputAction: TextInputAction.done,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: _decoration(
                              'Confirm password', Icons.lock_outline),
                          validator: (value) => value != _password.text ||
                                  (value?.isEmpty ?? true)
                              ? 'Your passwords must match.'
                              : null,
                          onFieldSubmitted: (_) => _submit(),
                        ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 18),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(_error!,
                                  style: const TextStyle(
                                      color: Color(0xFFF5E4A0), height: 1.5)),
                            ),
                          ),
                        const SizedBox(height: 24),
                        FilledButton(
                          key: const Key('signup_submit'),
                          onPressed: _busy ? null : _submit,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: _busy
                              ? const SizedBox.square(
                                  dimension: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: ConnectlyTheme.navy))
                              : const Text('Create account',
                                  style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
