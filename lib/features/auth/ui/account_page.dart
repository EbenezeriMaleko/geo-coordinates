import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import 'forgot_password_page.dart';
import 'login_page.dart';
import 'register_page.dart';

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
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Account', style: TextStyle(color: Colors.black87)),
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
              icon: const Icon(Icons.refresh, color: Colors.black87),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (!session.isLoggedIn) ...[
            const _HeroCard(
              title: 'Cloud Sync Access',
              subtitle:
                  'Sign in only when you want to sync local data to the server and manage your account.',
            ),
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
                ],
              ),
            ),
            const SizedBox(height: 16),
            const _SectionLabel('Verification'),
            _PanelCard(
              child: _ActionTile(
                title: session.isVerified
                    ? 'Email verified'
                    : 'Resend verification email',
                subtitle: session.isVerified
                    ? 'Your account email is already verified'
                    : 'Send a new verification email to ${user?.email ?? ''}',
                onTap: session.isVerified
                    ? null
                    : () async {
                        final result = await ref
                            .read(resendVerificationProvider.notifier)
                            .send();
                        if (!context.mounted || result == null) return;
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(result.message)));
                      },
                trailing: session.isVerified
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : const Icon(Icons.chevron_right, color: Colors.black45),
              ),
            ),
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
                trailing: const Icon(Icons.logout, color: Colors.red),
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

  static Widget _divider() => Divider(height: 1, color: Colors.grey.shade300);
}

class _HeroCard extends StatelessWidget {
  final String title;
  final String subtitle;

  const _HeroCard({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF001F3F),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
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
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
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
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isVerified
                    ? const Color(0xFFE8F7EE)
                    : const Color(0xFFFFF4E5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                isVerified ? 'Email verified' : 'Email not verified',
                style: TextStyle(
                  color: isVerified
                      ? const Color(0xFF1B7F46)
                      : const Color(0xFFB26A00),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
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
