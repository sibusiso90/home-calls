import 'package:fade_call/core/theme.dart';
import 'package:fade_call/data/api_exception.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/state/providers.dart';
import 'package:fade_call/ui/widgets/fade_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pick a role, then sign in with a name and phone number (demo login).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _passcode = TextEditingController();
  Role _role = Role.client;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _passcode.dispose();
    super.dispose();
  }

  /// Accepts 082 123 4567 or +27 82 123 4567 and returns +27821234567.
  static String? normalisePhone(String input) {
    final digits = input.replaceAll(RegExp(r'[^\d+]'), '');
    return switch (digits) {
      _ when RegExp(r'^0\d{9}$').hasMatch(digits) =>
        '+27${digits.substring(1)}',
      _ when RegExp(r'^\+27\d{9}$').hasMatch(digits) => digits,
      _ when RegExp(r'^27\d{9}$').hasMatch(digits) => '+$digits',
      _ => null,
    };
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(sessionProvider.notifier)
          .login(
            role: _role,
            name: _name.text.trim(),
            phone: normalisePhone(_phone.text)!,
            passcode: _role == Role.operator ? _passcode.text : null,
          );
    } on ApiException catch (e) {
      setState(
        () => _error = e.code == 'forbidden' || e.isUnauthorized
            ? (_role == Role.operator
                  ? 'That operator passcode is not right.'
                  : e.message)
            : e.message,
      );
    } on Object catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final form = _buildForm(context);
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            const Expanded(child: _BrandPanel(expanded: true)),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(Gap.xxl),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: form,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            const _BrandPanel(expanded: false),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Gap.md + 4,
                Gap.lg,
                Gap.md + 4,
                Gap.xxl,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: form,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) => Form(
    key: _form,
    child: AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Sign in', style: context.text.headlineMedium),
          const SizedBox(height: Gap.xs),
          Text(
            'Choose how you use Fade Call today.',
            style: context.text.bodyMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Gap.lg),
          for (final role in Role.values) ...[
            _RoleCard(
              role: role,
              selected: _role == role,
              onTap: () => setState(() {
                _role = role;
                _error = null;
              }),
            ),
            const SizedBox(height: Gap.sm + 2),
          ],
          const SizedBox(height: Gap.md),
          TextFormField(
            key: const ValueKey('login-name'),
            controller: _name,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.name],
            decoration: const InputDecoration(
              labelText: 'Your name',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            validator: (v) =>
                (v ?? '').trim().length < 2 ? 'Enter your name' : null,
          ),
          const SizedBox(height: Gap.md),
          TextFormField(
            key: const ValueKey('login-phone'),
            controller: _phone,
            keyboardType: TextInputType.phone,
            textInputAction: _role == Role.operator
                ? TextInputAction.next
                : TextInputAction.done,
            autofillHints: const [AutofillHints.telephoneNumber],
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d+ ]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Phone number',
              hintText: '082 123 4567',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
            validator: (v) => normalisePhone(v ?? '') == null
                ? 'Enter a South African number, like 082 123 4567'
                : null,
            onFieldSubmitted: (_) {
              if (_role != Role.operator) _submit().ignore();
            },
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: _role == Role.operator
                ? Padding(
                    padding: const EdgeInsets.only(top: Gap.md),
                    child: TextFormField(
                      key: const ValueKey('login-passcode'),
                      controller: _passcode,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Operator passcode',
                        prefixIcon: Icon(Icons.lock_outline_rounded),
                      ),
                      validator: (v) =>
                          _role == Role.operator && (v ?? '').isEmpty
                          ? 'Enter the operator passcode'
                          : null,
                      onFieldSubmitted: (_) => _submit().ignore(),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          if (_error != null) ...[
            const SizedBox(height: Gap.md),
            Text(
              _error!,
              key: const ValueKey('login-error'),
              style: context.text.bodyMedium?.copyWith(
                color: context.status.fail,
              ),
            ),
          ],
          const SizedBox(height: Gap.lg),
          FilledButton(
            key: const ValueKey('login-submit'),
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text('Continue as ${_role.label.toLowerCase()}'),
          ),
          const SizedBox(height: Gap.md),
          Text(
            'Demo sign-in: the same name and number brings you back to the same account.',
            textAlign: TextAlign.center,
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.selected,
    required this.onTap,
  });

  final Role role;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, blurb) = switch (role) {
      Role.client => (
        Icons.chair_outlined,
        'Get a quote and book a barber at home',
      ),
      Role.barber => (
        Icons.content_cut_rounded,
        'Get verified and take home-call jobs',
      ),
      Role.operator => (
        Icons.admin_panel_settings_outlined,
        'Approve barbers, review jobs and disputes',
      ),
    };
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        key: ValueKey('role-${role.name}'),
        color: selected ? Palette.forest : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: selected ? Palette.forest : Palette.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: selected ? Palette.brass : Palette.sand,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(icon, color: Palette.charcoal),
                  ),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        role.label,
                        style: context.text.titleMedium?.copyWith(
                          color: selected ? Palette.cream : Palette.charcoal,
                        ),
                      ),
                      Text(
                        blurb,
                        style: context.text.bodySmall?.copyWith(
                          color: selected
                              ? Palette.cream.withValues(alpha: 0.8)
                              : Palette.ink,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: selected ? Palette.brass : Palette.line,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final cream = Palette.cream.withValues(alpha: 0.82);
    final content = Column(
      mainAxisAlignment: expanded
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Palette.brass, width: 2),
              ),
              child: SizedBox.square(
                dimension: 44,
                child: Center(
                  child: Text(
                    'F',
                    style: context.text.titleLarge?.copyWith(
                      color: Palette.cream,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: Gap.sm + 4),
            Expanded(
              child: Text(
                'Fade Call',
                overflow: TextOverflow.ellipsis,
                style: context.text.titleLarge?.copyWith(color: Palette.cream),
              ),
            ),
            const MockBadge(onDark: true),
          ],
        ),
        SizedBox(height: expanded ? Gap.xxl : Gap.lg),
        Text(
          'Verified barbers,\nat your door.',
          style:
              (expanded
                      ? context.text.displayMedium
                      : context.text.headlineLarge)
                  ?.copyWith(color: Palette.cream, height: 1.05),
        ),
        const SizedBox(height: Gap.md),
        Text(
          'Home-call cuts in Midrand and Centurion. Every job is checked '
          'before the barber is paid.',
          style: context.text.bodyLarge?.copyWith(color: cream),
        ),
        const SizedBox(height: Gap.lg),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: Palette.brass.withValues(alpha: 0.9),
                width: 3,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: Gap.sm + 4),
            child: Text(
              'No verified job, no rating.',
              style: context.text.titleMedium?.copyWith(color: Palette.brass),
            ),
          ),
        ),
      ],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Palette.forest, Palette.forestDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: expanded
            ? null
            : const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.all(expanded ? Gap.xxl * 1.5 : Gap.lg),
          child: content,
        ),
      ),
    );
  }
}
