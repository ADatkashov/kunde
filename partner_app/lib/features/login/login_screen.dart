import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../core/error_text.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';

/// Compile-time switch: only DEV builds show the synthetic OTP hint.
const bool kDevOtpHint = bool.fromEnvironment('DEV_OTP_HINT');

class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.controller, super.key});
  final AppController controller;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  String get _normalizedPhone {
    final digits = _phone.text.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.startsWith('+')) return digits;
    if (digits.startsWith('8') && digits.length == 11) {
      return '+7${digits.substring(1)}';
    }
    if (digits.startsWith('7') && digits.length == 11) return '+$digits';
    return digits;
  }

  bool get _phoneValid => RegExp(r'^\+\d{10,15}$').hasMatch(_normalizedPhone);

  Future<void> _submit() async {
    final s = S.of(context);
    if (_busy) return; // double-tap guard
    if (!_phoneValid) {
      setState(() => _error = s.invalidPhone);
      return;
    }
    if (_codeSent && _code.text.trim().length < 4) {
      setState(() => _error = s.invalidCode);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!_codeSent) {
        await widget.controller.requestOtp(_normalizedPhone);
        if (mounted) setState(() => _codeSent = true);
      } else {
        await widget.controller.verifyOtp(_normalizedPhone, _code.text.trim());
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = errorText(s, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final notice = widget.controller.notice;
    final configured = widget.controller.apiConfigured;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(Gap.xl),
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: 72,
                    height: 72,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: context.colors.primary,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Icon(Icons.storefront_rounded,
                        size: 38, color: context.colors.onPrimary),
                  ),
                ),
                const SizedBox(height: Gap.xl),
                Semantics(
                  header: true,
                  child: Text(s.loginTitle, style: context.text.headlineMedium),
                ),
                const SizedBox(height: Gap.sm),
                Text(s.loginSubtitle,
                    style: context.text.bodyLarge
                        ?.copyWith(color: context.colors.onSurfaceVariant)),
                const SizedBox(height: Gap.xl),
                if (notice != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Gap.lg),
                    child: _Notice(
                      text: notice == SignOutNotice.sessionExpired
                          ? s.sessionExpired
                          : s.accessRevokedBody,
                    ),
                  ),
                if (!configured)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Gap.lg),
                    child: _Notice(text: s.apiNotConfigured, error: true),
                  ),
                TextField(
                  controller: _phone,
                  enabled: !_codeSent && !_busy,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s()-]')),
                  ],
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: s.phoneLabel,
                    hintText: s.phoneHint,
                    prefixIcon: const Icon(Icons.phone_iphone_rounded),
                  ),
                ),
                if (_codeSent) ...[
                  const SizedBox(height: Gap.md),
                  Text(s.codeSentTo(_normalizedPhone),
                      style: context.text.bodyMedium),
                  const SizedBox(height: Gap.md),
                  TextField(
                    controller: _code,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    maxLength: 8,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: s.codeLabel,
                      counterText: '',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                    ),
                  ),
                  if (kDevOtpHint)
                    Padding(
                      padding: const EdgeInsets.only(top: Gap.sm),
                      child: Text(s.devCodeHint, style: context.text.bodySmall),
                    ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Gap.md),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(_error!,
                          style: context.text.bodyMedium
                              ?.copyWith(color: context.colors.error)),
                    ),
                  ),
                const SizedBox(height: Gap.lg),
                FilledButton(
                  onPressed: _busy || !configured ? null : _submit,
                  child: Text(_busy
                      ? s.pleaseWait
                      : _codeSent
                          ? s.signIn
                          : s.getCode),
                ),
                if (_codeSent)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _codeSent = false;
                              _code.clear();
                              _error = null;
                            }),
                    child: Text(s.changeNumber),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.error = false});
  final String text;
  final bool error;
  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(Gap.md),
        decoration: BoxDecoration(
          color: error ? context.colors.errorContainer : tones.warningContainer,
          borderRadius: BorderRadius.circular(Radii.control),
        ),
        child: Row(children: [
          Icon(error ? Icons.error_outline : Icons.info_outline,
              color: error ? context.colors.error : tones.warning),
          const SizedBox(width: Gap.md),
          Expanded(child: Text(text, style: context.text.bodyMedium)),
        ]),
      ),
    );
  }
}
