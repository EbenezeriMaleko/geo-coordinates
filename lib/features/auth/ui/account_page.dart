import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/auth_provider.dart';
import 'forgot_password_page.dart';
import 'login_page.dart';
import 'register_page.dart';
import 'package:hugeicons/hugeicons.dart';

class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionProvider);
    final user = session.user;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedArrowLeft01,
            color: Colors.black87,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Account',
          style: GoogleFonts.inter(color: Colors.black87, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (session.isLoggedIn)
            IconButton(
              onPressed: () async {
                await ref
                    .read(authSessionProvider.notifier)
                    .refreshCurrentUser();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Account refreshed')),
                  );
                }
              },
              icon: const HugeIcon(
                icon: HugeIcons.strokeRoundedRefresh,
                color: Colors.black87,
                size: 20,
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (!session.isLoggedIn) ...[
            const SizedBox(height: 16),
            _PanelCard(
              child: Column(
                children: [
                  _ActionTile(
                    title: 'Sign In',
                    subtitle: 'Connect this device to your cloud account',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              const LoginPage(returnToPreviousPage: true),
                        ),
                      );
                    },
                  ),
                  _divider(),
                  _ActionTile(
                    title: 'Create account',
                    subtitle: 'Register a new account for sync access',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const RegisterPage(),
                        ),
                      );
                    },
                  ),
                  _divider(),
                  _ActionTile(
                    title: 'Forgot password',
                    subtitle: 'Request password reset by email',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ForgotPasswordPage(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ] else ...[
            _ProfileCard(
              name: user?.name.isNotEmpty == true ? user!.name : 'Account',
              email: user?.email ?? '',
              phone: user?.phone,
              isVerified: session.isVerified,
            ),
            const SizedBox(height: 16),
            const _SectionLabel('Profile'),
            _PanelCard(
              child: Column(
                children: [
                  _ActionTile(
                    title: 'Update profile',
                    subtitle: 'Edit name, email and phone number',
                    onTap: () => _showUpdateProfileSheet(context),
                  ),
                  _divider(),
                  _ActionTile(
                    title: 'Change password',
                    subtitle: 'Update your account password',
                    onTap: () => _showChangePasswordSheet(context),
                  ),
                  _divider(),
                  _ActionTile(
                    title: 'Open TaREF web app',
                    subtitle: 'Manage your data at ardhi.co.tz',
                    onTap: () => _openArdhiWebApp(context),
                    trailing: const HugeIcon(
                      icon: HugeIcons.strokeRoundedGlobe02,
                      color: Color(0xFF001F3F),
                    ),
                  ),
                ],
              ),
            ),
            if (!session.isVerified) ...[
              const SizedBox(height: 16),
              const _SectionLabel('Verification'),
              _PanelCard(
                child: _ActionTile(
                  title: 'Resend verification email',
                  subtitle:
                      'Send a new verification email to ${user?.email ?? ''}',
                  onTap: () async {
                    final result = await ref
                        .read(resendVerificationProvider.notifier)
                        .send();
                    if (!context.mounted || result == null) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(result.message)));
                  },
                  trailing: const HugeIcon(
                    icon: HugeIcons.strokeRoundedArrowRight01,
                    color: Colors.black45,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            const _SectionLabel('Session'),
            _PanelCard(
              child: _ActionTile(
                title: 'Logout',
                subtitle: 'Stop cloud sync on this device and keep local data',
                onTap: () async {
                  await ref.read(authSessionProvider.notifier).logout();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Logged out successfully')),
                  );
                },
                titleColor: Colors.red,
                trailing: const HugeIcon(
                  icon: HugeIcons.strokeRoundedLogout01,
                  color: Colors.red,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const _SectionLabel('Danger zone'),
            _PanelCard(
              child: _ActionTile(
                title: 'Delete account',
                subtitle:
                    'Permanently delete your account. You will need your password and email access to confirm.',
                onTap: () => _showDeleteAccountSheet(context),
                titleColor: const Color(0xFFB42318),
                trailing: const Icon(
                  Icons.delete_forever_outlined,
                  color: Color(0xFFB42318),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showUpdateProfileSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _UpdateProfileSheet(),
    );
  }

  Future<void> _showChangePasswordSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ChangePasswordSheet(),
    );
  }

  Future<void> _showDeleteAccountSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _DeleteAccountSheet(),
    );
  }

  Future<void> _openArdhiWebApp(BuildContext context) async {
    final uri = Uri.parse('https://ardhi.co.tz');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (ok) return;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open Ardhi web app')),
    );
  }

  static Widget _divider() => Divider(height: 1, color: Colors.grey.shade300);
}

class _ProfileCard extends StatelessWidget {
  final String name;
  final String email;
  final String? phone;
  final bool isVerified;

  const _ProfileCard({
    required this.name,
    required this.email,
    required this.phone,
    required this.isVerified,
  });

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: const Color(0xFF001F3F),
                  child: Text(
                    name.isEmpty
                        ? '?'
                        : name.trim().characters.first.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          if (isVerified)
                            const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: HugeIcon(
                                icon: HugeIcons.strokeRoundedCheckmarkCircle01,
                                color: Color(0xFF1B7F46),
                                size: 22,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email,
                        style: const TextStyle(color: Colors.black54),
                      ),
                      if ((phone ?? '').trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            phone!,
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (!isVerified) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4E5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Email not verified',
                  style: TextStyle(
                    color: Color(0xFFB26A00),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF001F3F),
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    );
  }
}

class _PanelCard extends StatelessWidget {
  final Widget child;

  const _PanelCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 0,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _ActionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Color? titleColor;
  final Widget? trailing;

  const _ActionTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.titleColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: titleColor ?? Colors.black87,
        ),
      ),
      subtitle: Text(subtitle),
      trailing:
          trailing ?? const Icon(Icons.chevron_right, color: Colors.black45),
      onTap: onTap,
    );
  }
}

class _UpdateProfileSheet extends ConsumerStatefulWidget {
  const _UpdateProfileSheet();

  @override
  ConsumerState<_UpdateProfileSheet> createState() =>
      _UpdateProfileSheetState();
}

class _UpdateProfileSheetState extends ConsumerState<_UpdateProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authSessionProvider).user;
    _nameController = TextEditingController(text: user?.name ?? '');
    _emailController = TextEditingController(text: user?.email ?? '');
    _phoneController = TextEditingController(text: user?.phone ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final user = await ref
        .read(updateProfileProvider.notifier)
        .submit(
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
          phone: _phoneController.text.trim(),
        );
    if (!mounted || user == null) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile updated successfully')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(updateProfileProvider);
    final isLoading = state.isLoading;
    final error = state.hasError ? state.error.toString() : null;

    return _SheetFrame(
      title: 'Update profile',
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (error != null) ...[
              _SheetError(message: error),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Full name',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Name is required'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email address',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Email is required'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone number',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: isLoading ? null : _submit,
                child: isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChangePasswordSheet extends ConsumerStatefulWidget {
  const _ChangePasswordSheet();

  @override
  ConsumerState<_ChangePasswordSheet> createState() =>
      _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends ConsumerState<_ChangePasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final result = await ref
        .read(changePasswordProvider.notifier)
        .submit(
          currentPassword: _currentController.text,
          password: _newController.text,
          passwordConfirmation: _confirmController.text,
        );
    if (!mounted || result == null || !result.success) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(changePasswordProvider);
    final isLoading = state.isLoading;
    final error = state.hasError ? state.error.toString() : null;

    return _SheetFrame(
      title: 'Change password',
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (error != null) ...[
              _SheetError(message: error),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _currentController,
              obscureText: _obscureCurrent,
              decoration: _passwordDecoration(
                'Current password',
                _obscureCurrent,
                () => setState(() => _obscureCurrent = !_obscureCurrent),
              ),
              validator: (value) => value == null || value.isEmpty
                  ? 'Current password is required'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _newController,
              obscureText: _obscureNew,
              decoration: _passwordDecoration(
                'New password',
                _obscureNew,
                () => setState(() => _obscureNew = !_obscureNew),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'New password is required';
                }
                if (value.length < 8) return 'Minimum 8 characters';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirmController,
              obscureText: _obscureConfirm,
              decoration: _passwordDecoration(
                'Confirm new password',
                _obscureConfirm,
                () => setState(() => _obscureConfirm = !_obscureConfirm),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Confirm your new password';
                }
                if (value != _newController.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: isLoading ? null : _submit,
                child: isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Update password'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _passwordDecoration(
    String label,
    bool obscure,
    VoidCallback toggle,
  ) {
    return InputDecoration(
      labelText: label,
      prefixIcon: const Icon(Icons.lock_outline_rounded),
      suffixIcon: IconButton(
        onPressed: toggle,
        icon: Icon(
          obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        ),
      ),
    );
  }
}

enum _AccountDeletionStage { request, confirm }

class _DeleteAccountSheet extends ConsumerStatefulWidget {
  const _DeleteAccountSheet();

  @override
  ConsumerState<_DeleteAccountSheet> createState() =>
      _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends ConsumerState<_DeleteAccountSheet> {
  final _requestFormKey = GlobalKey<FormState>();
  final _confirmFormKey = GlobalKey<FormState>();
  late final TextEditingController _passwordController;
  late final TextEditingController _codeController;
  bool _obscurePassword = true;
  _AccountDeletionStage _stage = _AccountDeletionStage.request;
  String? _bannerMessage;
  bool _bannerIsError = false;

  @override
  void initState() {
    super.initState();
    _passwordController = TextEditingController();
    _codeController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(accountDeletionProvider.notifier).reset();
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    if (!(_requestFormKey.currentState?.validate() ?? false)) return;

    final response = await ref
        .read(accountDeletionProvider.notifier)
        .requestDeletion(password: _passwordController.text);

    if (!mounted || response == null) return;

    setState(() {
      _bannerMessage = response.message;
      _bannerIsError = !response.success;
    });

    if (response.success) {
      setState(() {
        _stage = _AccountDeletionStage.confirm;
      });
      _passwordController.clear();
      _codeController.clear();
      return;
    }
  }

  Future<void> _confirmDeletion() async {
    if (!(_confirmFormKey.currentState?.validate() ?? false)) return;

    final response = await ref
        .read(accountDeletionProvider.notifier)
        .confirmDeletion(code: _codeController.text);

    if (!mounted || response == null) return;

    setState(() {
      _bannerMessage = response.message;
      _bannerIsError = !response.success;
    });

    if (!response.success) return;

    final messenger = ScaffoldMessenger.of(context);
    await ref.read(authSessionProvider.notifier).clearLocalSession();
    ref.read(accountDeletionProvider.notifier).reset();
    if (!mounted) return;
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(content: Text(response.message)));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(accountDeletionProvider);
    final isLoading = state.isLoading;
    final providerError = state.hasError ? state.error.toString() : null;
    final session = ref.watch(authSessionProvider);
    final email = session.user?.email ?? '';
    final bannerText = _bannerIsError
        ? (providerError ?? _bannerMessage)
        : (_bannerMessage ?? providerError);

    return _SheetFrame(
      title: 'Delete account',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F0),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFB42318),
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'This action is irreversible. All tokens will be revoked and your account data will be deleted after code confirmation.',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.45,
                      color: const Color(0xFF7A271A),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StepChip(
                  label: '1 Request code',
                  active: _stage == _AccountDeletionStage.request,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StepChip(
                  label: '2 Confirm deletion',
                  active: _stage == _AccountDeletionStage.confirm,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (bannerText != null) ...[
            _SheetError(message: bannerText),
            const SizedBox(height: 14),
          ],
          Text(
            'Email address',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Text(
              email.isEmpty ? 'No email found' : email,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          const SizedBox(height: 18),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _stage == _AccountDeletionStage.request
                ? Form(
                    key: _requestFormKey,
                    child: Column(
                      key: const ValueKey('request-stage'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          autofillHints: const [AutofillHints.password],
                          decoration: InputDecoration(
                            labelText: 'Current password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                          ),
                          validator: (value) => value == null || value.isEmpty
                              ? 'Current password is required'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'A verification code will be sent to your email address. The request is throttled to 3 times per minute.',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            height: 1.45,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: isLoading ? null : _requestCode,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFB42318),
                              foregroundColor: Colors.white,
                            ),
                            child: isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Send verification code'),
                          ),
                        ),
                      ],
                    ),
                  )
                : Form(
                    key: _confirmFormKey,
                    child: Column(
                      key: const ValueKey('confirm-stage'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _codeController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Verification code',
                            prefixIcon: Icon(Icons.pin_outlined),
                            helperText:
                                'Enter the 6-digit code sent to your email.',
                          ),
                          validator: (value) =>
                              value == null || value.trim().length != 6
                              ? 'Enter the 6-digit verification code'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'The confirm request is throttled to 6 times per minute.',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            height: 1.45,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: isLoading ? null : _confirmDeletion,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFB42318),
                              foregroundColor: Colors.white,
                            ),
                            child: isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Delete my account'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: isLoading
                              ? null
                              : () {
                                  setState(() {
                                    _stage = _AccountDeletionStage.request;
                                    _bannerMessage = null;
                                    _bannerIsError = false;
                                  });
                                  _codeController.clear();
                                },
                          child: const Text('Back to password step'),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  final String label;
  final bool active;

  const _StepChip({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFFFF1F0) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active ? const Color(0xFFFECACA) : Colors.grey.shade300,
        ),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: active ? const Color(0xFFB42318) : Colors.black54,
        ),
      ),
    );
  }
}

class _SheetFrame extends StatelessWidget {
  final String title;
  final Widget child;

  const _SheetFrame({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 12, 12, bottomInset + 12),
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 18),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetError extends StatelessWidget {
  final String message;

  const _SheetError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          fontSize: 13,
          color: Color(0xFFDC2626),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
