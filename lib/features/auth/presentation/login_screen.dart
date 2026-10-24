import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/connectly_theme.dart';
import '../data/login_preferences.dart';
import '../domain/auth_models.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    required this.onContinueAsGuest,
    this.preferences,
    this.onSignIn,
    this.onCreateAccount,
    this.initialMessage,
    super.key,
  });

  final VoidCallback onContinueAsGuest;
  final LoginPreferences? preferences;
  final Future<void> Function(String email, String password)? onSignIn;
  final VoidCallback? onCreateAccount;
  final String? initialMessage;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _hidePassword = true;
  bool _rememberEmail = false;
  bool _busy = false;
  bool _preferencesFailed = false;
  String? _message;

  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  @override
  void initState() {
    super.initState();
    final savedEmail = widget.preferences?.rememberedEmail;
    _emailController.text = savedEmail ?? '';
    _rememberEmail = savedEmail != null && savedEmail.isNotEmpty;
    _message = widget.initialMessage;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _saveEmail() async {
    final email = _emailController.text.trim();
    try {
      await widget.preferences?.saveEmail(
        _rememberEmail && _emailPattern.hasMatch(email) ? email : null,
      );
    } catch (_) {
      if (mounted) {
        setState(() => _preferencesFailed = true);
      }
    }
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _message = null;
    });
    await _saveEmail();
    if (!mounted) return;

    try {
      final signIn = widget.onSignIn;
      if (signIn == null) {
        setState(() {
          _message = 'Account sign-in is coming soon. '
              'You can explore as a guest for now.';
        });
      } else {
        await signIn(_emailController.text.trim(), _passwordController.text);
        TextInput.finishAutofillContext();
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = 'We couldn\'t sign you in. '
              'Check your details and try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _continueAsGuest() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    await _saveEmail();
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onContinueAsGuest();
  }

  InputDecoration _decoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF8F9BB3), fontSize: 16),
      prefixIcon: Icon(icon, size: 21, color: const Color(0xFFB9C4D8)),
      filled: true,
      fillColor: ConnectlyTheme.navy,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF465570)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF465570)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: ConnectlyTheme.yellow, width: 1.5),
      ),
      errorMaxLines: 2,
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    );
  }

  Widget _form(bool compact) {
    return Container(
      padding: EdgeInsets.all(compact ? 20 : 32),
      decoration: BoxDecoration(
        color: ConnectlyTheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF40516F)),
      ),
      child: AutofillGroup(
        onDisposeAction: AutofillContextAction.cancel,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'A little closer to your people.',
                style: TextStyle(
                  color: Color(0xFFD4DCEB),
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
              SizedBox(height: compact ? 20 : 28),
              _fieldLabel('Email address'),
              TextFormField(
                key: const Key('login_email'),
                controller: _emailController,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(fontSize: 16),
                decoration: _decoration('you@example.com', Icons.mail_outline),
                validator: (value) {
                  final email = value?.trim() ?? '';
                  if (email.isEmpty) return 'Enter your email address.';
                  if (!_emailPattern.hasMatch(email)) {
                    return 'Enter a valid email address.';
                  }
                  return null;
                },
              ),
              SizedBox(height: compact ? 16 : 22),
              _fieldLabel('Password'),
              TextFormField(
                key: const Key('login_password'),
                controller: _passwordController,
                enabled: !_busy,
                obscureText: _hidePassword,
                keyboardType: TextInputType.visiblePassword,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(fontSize: 16),
                onFieldSubmitted: (_) => _submit(),
                decoration:
                    _decoration('Enter your password', Icons.lock_outline)
                        .copyWith(
                  suffixIcon: IconButton(
                    tooltip: _hidePassword ? 'Show password' : 'Hide password',
                    onPressed: _busy
                        ? null
                        : () => setState(() => _hidePassword = !_hidePassword),
                    icon: Icon(
                      _hidePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 21,
                      color: const Color(0xFFB9C4D8),
                    ),
                  ),
                ),
                validator: (value) => value == null || value.isEmpty
                    ? 'Enter your password.'
                    : null,
              ),
              const SizedBox(height: 10),
              Material(
                type: MaterialType.transparency,
                child: CheckboxListTile(
                  value: _rememberEmail,
                  onChanged: _busy || widget.preferences == null
                      ? null
                      : (value) async {
                          setState(() => _rememberEmail = value ?? false);
                          if (!_rememberEmail) await _saveEmail();
                        },
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  visualDensity: VisualDensity.compact,
                  title: const Text(
                    'Remember my email',
                    style: TextStyle(fontSize: 14, color: Color(0xFFD4DCEB)),
                  ),
                  activeColor: ConnectlyTheme.yellow,
                  checkColor: ConnectlyTheme.navy,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              if (_preferencesFailed || widget.preferences == null)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Remembering your email is unavailable on this device.',
                    style: TextStyle(color: Color(0xFFD4DCEB), fontSize: 13),
                  ),
                ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 18),
                  child: Semantics(
                    liveRegion: true,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: ConnectlyTheme.navy,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _message!,
                        style: const TextStyle(
                          color: Color(0xFFF5E4A0),
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              FilledButton(
                key: const Key('login_submit'),
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor: ConnectlyTheme.yellow,
                  foregroundColor: ConnectlyTheme.navy,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Urbanist',
                  ),
                ),
                child: _busy
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: ConnectlyTheme.navy,
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(child: Text('Sign in')),
                          SizedBox(width: 12),
                          Icon(Icons.arrow_forward_rounded, size: 21),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'Urbanist'),
      ),
      child: Scaffold(
        bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom > 0
            ? null
            : SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    if (widget.onCreateAccount != null)
                      TextButton(
                        onPressed: _busy ? null : widget.onCreateAccount,
                        style: TextButton.styleFrom(
                          foregroundColor: ConnectlyTheme.yellow,
                          minimumSize: const Size(48, 48),
                          textStyle: const TextStyle(
                            fontFamily: 'Urbanist',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: const Text('Create account'),
                      ),
                    TextButton.icon(
                      key: const Key('login_guest'),
                      onPressed: _busy ? null : _continueAsGuest,
                      icon: const Icon(Icons.explore_outlined, size: 19),
                      label: const Text('Continue as a guest'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        minimumSize: const Size(48, 48),
                        textStyle: const TextStyle(
                          fontFamily: 'Urbanist',
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        body: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              final compact = !wide &&
                  (constraints.maxWidth < 380 || constraints.maxHeight < 800);
              return Center(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 20 : 28,
                    vertical: wide ? 48 : (compact ? 16 : 28),
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: wide ? 1000 : 440),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _Brand(),
                        SizedBox(height: wide ? 64 : (compact ? 22 : 28)),
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Expanded(child: _Welcome(wide: true)),
                              const SizedBox(width: 80),
                              SizedBox(width: 420, child: _form(false)),
                            ],
                          )
                        else ...[
                          _Welcome(wide: false, compact: compact),
                          SizedBox(height: compact ? 20 : 28),
                          _form(compact),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: ConnectlyTheme.yellow,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.hub_rounded,
            color: ConnectlyTheme.navy,
            size: 27,
          ),
        ),
        const SizedBox(width: 12),
        const Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'connectly',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: -1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.wide, this.compact = false});

  final bool wide;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'CONNECT. SHARE. BELONG.',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
            color: ConnectlyTheme.yellow,
          ),
        ),
        SizedBox(height: compact ? 10 : 14),
        Text(
          wide ? 'Welcome\nback.' : 'Welcome back.',
          style: TextStyle(
            fontSize: wide ? 76 : (compact ? 36 : 40),
            height: 1.05,
            fontWeight: FontWeight.w700,
            letterSpacing: -2,
          ),
        ),
        SizedBox(height: compact ? 10 : 18),
        Text(
          compact
              ? 'Your community is right here.'
              : 'Familiar faces. New conversations.\nYour community is right here.',
          style: TextStyle(
            fontSize: 16,
            height: 1.65,
            color: Color(0xFFB8C5DA),
          ),
        ),
        if (wide) ...[
          const SizedBox(height: 40),
          const Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _ConnectionIcon(Icons.people_outline_rounded),
              _ConnectionIcon(Icons.place_outlined),
              _ConnectionIcon(Icons.chat_bubble_outline_rounded),
            ],
          ),
        ],
      ],
    );
  }
}

class _ConnectionIcon extends StatelessWidget {
  const _ConnectionIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: ConnectlyTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF40516F)),
      ),
      child: Icon(icon, color: ConnectlyTheme.yellow, size: 26),
    );
  }
}
