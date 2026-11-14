import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'auth_repository.dart';
import 'phone_auth_gateway.dart';
import 'phone_auth_strings.dart';

/// Formats up to ten national digits as `XXX XXX XX XX` (the `+7` prefix is fixed).
class NationalPhoneFormatter extends TextInputFormatter {
  static String format(String digits) {
    final d = digits.length > 10 ? digits.substring(0, 10) : digits;
    final groups = <String>[];
    var i = 0;
    for (final size in [3, 3, 2, 2]) {
      if (i >= d.length) break;
      final end = i + size > d.length ? d.length : i + size;
      groups.add(d.substring(i, end));
      i = end;
    }
    return groups.join(' ');
  }

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    // Pasted +7 / 8 prefixes of a full number are dropped.
    if (digits.length == 11 &&
        (digits.startsWith('7') || digits.startsWith('8'))) {
      digits = digits.substring(1);
    }
    final text = format(digits);
    return TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

/// Two-step phone sign-in: number, then a six-digit code. On success calls
/// [onSignedIn] with the issued tokens; the caller owns session storage and navigation.
class PhoneLoginFlow extends StatefulWidget {
  const PhoneLoginFlow(
      {required this.gateway,
      required this.onSignedIn,
      this.devOtpHint = false,
      super.key});
  final PhoneAuthGateway gateway;
  final Future<void> Function(AuthTokens tokens) onSignedIn;
  final bool devOtpHint;

  @override
  State<PhoneLoginFlow> createState() => _PhoneLoginFlowState();
}

class _PhoneLoginFlowState extends State<PhoneLoginFlow> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _codeFocus = FocusNode();
  bool _codeStep = false;
  bool _busy = false;
  PhoneAuthFailure? _error;
  int _cooldown = 0;
  Timer? _timer;

  String get _digits => _phone.text.replaceAll(RegExp(r'\D'), '');
  String get _e164 => '+7$_digits';

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _timer?.cancel();
    setState(() => _cooldown = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _cooldown <= 1) {
        timer.cancel();
        if (mounted) setState(() => _cooldown = 0);
        return;
      }
      setState(() => _cooldown--);
    });
  }

  Future<void> _requestCode() async {
    if (_digits.length != 10) {
      setState(() => _error = PhoneAuthFailure.invalidPhone);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final challenge = await widget.gateway.requestOtp(_e164);
      if (!mounted) return;
      _code.clear();
      setState(() => _codeStep = true);
      _startCooldown(challenge.resendAfterSeconds);
      _codeFocus.requestFocus();
    } on PhoneAuthException catch (error) {
      if (mounted) setState(() => _error = error.failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify(String code) async {
    if (_busy || code.length != 6) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final tokens = await widget.gateway.verifyOtp(_e164, code);
      await widget.onSignedIn(tokens);
    } on PhoneAuthException catch (error) {
      if (mounted) {
        setState(() => _error = error.failure);
        _code.clear();
        _codeFocus.requestFocus();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = PhoneAuthStrings(context);
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          children: [
            Container(
              height: 72,
              width: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(22)),
              child: Icon(
                  _codeStep ? Icons.lock_outline : Icons.phone_iphone_rounded,
                  size: 36,
                  color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: 28),
            Text(_codeStep ? s.codeTitle : s.phoneTitle,
                style: theme.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(_codeStep ? s.sentTo('+7 ${_phone.text}') : s.phoneBody,
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 28),
            if (!_codeStep) _phoneStep(s, theme) else _codeStepView(s, theme),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline,
                          size: 20, color: theme.colorScheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(s.error(_error!),
                              key: const Key('phone-auth-error'),
                              style:
                                  TextStyle(color: theme.colorScheme.error))),
                    ]),
              ),
            ],
            const SizedBox(height: 24),
            Text(s.terms, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _phoneStep(PhoneAuthStrings s, ThemeData theme) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          key: const Key('phone-field'),
          controller: _phone,
          enabled: !_busy,
          autofocus: true,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.telephoneNumberNational],
          inputFormatters: [NationalPhoneFormatter()],
          style: theme.textTheme.titleLarge,
          onChanged: (_) => setState(() => _error = null),
          onSubmitted: (_) => _requestCode(),
          decoration: InputDecoration(
            labelText: s.phoneLabel,
            hintText: s.phoneHint,
            prefixText: '+7  ',
            prefixStyle: theme.textTheme.titleLarge,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('get-code'),
          onPressed: _busy || _digits.length != 10 ? null : _requestCode,
          style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16))),
          child: _busy
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5))
              : Text(s.getCode),
        ),
      ]);

  Widget _codeStepView(PhoneAuthStrings s, ThemeData theme) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _OtpBoxes(
            controller: _code,
            focusNode: _codeFocus,
            enabled: !_busy,
            hasError: _error == PhoneAuthFailure.invalidCode,
            onChanged: (value) {
              if (_error != null) setState(() => _error = null);
              if (value.length == 6) _verify(value);
            }),
        const SizedBox(height: 16),
        if (_busy)
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(width: 12),
            Text(s.verifying),
          ])
        else if (widget.devOtpHint)
          Container(
            key: const Key('dev-otp-hint'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: theme.colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(12)),
            child: Text(s.devHint,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.onTertiaryContainer)),
          ),
        const SizedBox(height: 12),
        TextButton(
          key: const Key('resend-code'),
          onPressed: _busy || _cooldown > 0 ? null : _requestCode,
          child: Text(_cooldown > 0 ? s.resendIn(_cooldown) : s.resend),
        ),
        TextButton(
          key: const Key('change-number'),
          onPressed: _busy
              ? null
              : () {
                  _timer?.cancel();
                  setState(() {
                    _codeStep = false;
                    _error = null;
                    _cooldown = 0;
                  });
                },
          child: Text(s.changeNumber),
        ),
      ]);
}

/// Six digit boxes driven by one invisible text field, so paste, autofill and
/// the system keyboard behave normally.
class _OtpBoxes extends StatelessWidget {
  const _OtpBoxes(
      {required this.controller,
      required this.focusNode,
      required this.enabled,
      required this.hasError,
      required this.onChanged});
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool hasError;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? focusNode.requestFocus : null,
      child: Stack(alignment: Alignment.center, children: [
        ListenableBuilder(
          listenable: Listenable.merge([controller, focusNode]),
          builder: (context, _) {
            final text = controller.text;
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(6, (i) {
                final active =
                    focusNode.hasFocus && i == text.length.clamp(0, 5);
                return Container(
                  width: 46,
                  height: 58,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        width: active ? 2 : 1,
                        color: hasError
                            ? theme.colorScheme.error
                            : active
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outlineVariant),
                  ),
                  child: Text(i < text.length ? text[i] : '',
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                );
              }),
            );
          },
        ),
        Positioned.fill(
          child: Opacity(
            opacity: 0.0,
            child: TextField(
              key: const Key('otp-field'),
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              autofocus: true,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              showCursor: false,
              enableInteractiveSelection: false,
              onChanged: onChanged,
            ),
          ),
        ),
      ]),
    );
  }
}
