import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:hugeicons/hugeicons.dart';
import '../../core/network/api_client.dart';
import '../auth/providers/auth_provider.dart';
import '../widget/app_backarrow.dart'; // adjust to your file name/path
import 'workspace_provider.dart';
import 'workspace_page_style.dart';

const Color _accent = Color(0xFF197568); // company accent
const Color _pageBackground = Color(0xFFF7F7F8);
const Color _cardBorder = Color(0xFFE8ECF0);
const Color _fieldFill = Color(0xFFF7F7F8);
const Color _amber = Color(0xFFB26A00);
const Color _amberSoft = Color(0xFFFFF4E0);

class CompanyCreationUnconfirmed implements Exception {
  const CompanyCreationUnconfirmed();
  @override
  String toString() =>
      'Company creation could not be confirmed. Check your workspace list before trying again.';
}

class CompanyCreateService {
  Future<CompanyWorkspace> create(
    String token,
    Map<String, dynamic> input,
  ) async {
    late final http.Response response;
    try {
      response = await ApiClient.postJson(
        '/companies',
        bearerToken: token,
        body: input,
      );
    } catch (_) {
      throw const CompanyCreationUnconfirmed();
    }
    if (response.statusCode >= 500 || response.statusCode == 408) {
      throw const CompanyCreationUnconfirmed();
    }
    Map? body;
    try {
      final value = jsonDecode(response.body);
      if (value is Map) body = value;
    } catch (_) {}
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(body?['message'] ?? 'Unable to create company.');
    }
    if (body?['data'] is! Map) throw const CompanyCreationUnconfirmed();
    final company = CompanyWorkspace.fromJson({
      'company': body!['data'],
      'role': 'owner',
    });
    if (company.id <= 0 || company.name.isEmpty) {
      throw const CompanyCreationUnconfirmed();
    }
    return company;
  }
}

final companyCreateServiceProvider = Provider<CompanyCreateService>(
  (ref) => CompanyCreateService(),
);

class CompanyCreatePage extends ConsumerStatefulWidget {
  const CompanyCreatePage({super.key});
  @override
  ConsumerState<CompanyCreatePage> createState() => _CompanyCreatePageState();
}

class _CompanyCreatePageState extends ConsumerState<CompanyCreatePage> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  late final token = ref.read(authSessionProvider).token;
  bool busy = false;
  bool uncertain = false;
  String? error;
  bool get available {
    final session = ref.read(authSessionProvider);
    return session.isLoggedIn && session.isVerified && session.token == token;
  }

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    phone.dispose();
    super.dispose();
  }

  Future<void> create() async {
    if (busy || uncertain || !available || !form.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final company = await ref
          .read(companyCreateServiceProvider)
          .create(token, {
            'name': name.text.trim(),
            if (email.text.trim().isNotEmpty) 'email': email.text.trim(),
            if (phone.text.trim().isNotEmpty) 'phone': phone.text.trim(),
          });
      if (!mounted || !available) return;
      await ref.read(workspaceProvider.notifier).refresh();
      if (!mounted || !available) return;
      Navigator.pop(context, company);
    } catch (failure) {
      if (mounted && available) {
        setState(() {
          uncertain = failure is CompanyCreationUnconfirmed;
          error = failure.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> checkWorkspaces() async {
    if (busy || !available) return;
    setState(() => busy = true);
    try {
      await ref.read(workspaceProvider.notifier).refresh();
      if (mounted && available) {
        if (ref.read(workspaceProvider).error != null) {
          setState(
            () => error =
                'Unable to refresh your workspace list. Try checking again before creating another company.',
          );
          return;
        }
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // ── UI helpers ────────────────────────────────────────────────

  InputDecoration _decoration(String label, dynamic icon, {String? hint}) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: width),
        );
    final errorColor = Theme.of(context).colorScheme.error;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      counterText: '',
      filled: true,
      fillColor: _fieldFill,
      labelStyle: const TextStyle(fontSize: 14, color: Colors.black54),
      floatingLabelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: _accent,
      ),
      prefixIcon: Padding(
        padding: const EdgeInsets.all(14),
        child: HugeIcon(icon: icon, color: Colors.black45, size: 20),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      border: border(_cardBorder),
      enabledBorder: border(_cardBorder),
      disabledBorder: border(_cardBorder),
      focusedBorder: border(_accent, 1.6),
      errorBorder: border(errorColor),
      focusedErrorBorder: border(errorColor, 1.6),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: Colors.black45,
      ),
    ),
  );

  Widget _card(List<Widget> children) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _cardBorder),
    ),
    child: Column(children: children),
  );

  Widget _infoRow(dynamic icon, String title, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: HugeIcon(icon: icon, color: _accent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner() {
    final scheme = Theme.of(context).colorScheme;
    final color = uncertain ? _amber : scheme.error;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: uncertain ? _amberSoft : scheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HugeIcon(
            icon: HugeIcons.strokeRoundedAlert02,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              error!,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: uncertain ? Colors.black87 : scheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _cardBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: uncertain
                ? OutlinedButton.icon(
                    onPressed: busy ? null : checkWorkspaces,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _accent,
                      side: const BorderSide(color: _accent),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const HugeIcon(
                            icon: HugeIcons.strokeRoundedRefresh,
                            color: _accent,
                            size: 18,
                          ),
                    label: Text(
                      busy ? 'Checking...' : 'Check workspaces',
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : FilledButton.icon(
                    onPressed: busy ? null : create,
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const HugeIcon(
                            icon: HugeIcons.strokeRoundedAddCircle,
                            color: Colors.white,
                            size: 18,
                          ),
                    label: Text(
                      busy ? 'Creating...' : 'Create company',
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authSessionProvider);
    final baseTheme = Theme.of(context);
    final enabled = !busy && !uncertain;

    return Theme(
      data: baseTheme.copyWith(
        colorScheme: baseTheme.colorScheme.copyWith(primary: _accent),
      ),
      child: PopScope(
        canPop: !busy,
        child: WorkspaceScaffold(
          company: true,
          appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            elevation: 0,
            leading: const AppBackButton(),
            title: const Text(
              'Create company',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            centerTitle: true,
          ),
          body: ColoredBox(
            color: _pageBackground,
            child: !available
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const HugeIcon(
                            icon: HugeIcons.strokeRoundedShield01,
                            color: Colors.black26,
                            size: 40,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Sign in with a verified account to create a company. Reopen this form if your account changed.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.45,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: Form(
                          key: form,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                            children: [
                              // Header
                              Center(
                                child: Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    color: _accent.withValues(alpha: 0.10),
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: const HugeIcon(
                                    icon: HugeIcons.strokeRoundedBuilding03,
                                    color: _accent,
                                    size: 34,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                'Set up your company',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'You will be the company owner.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: Colors.black54,
                                ),
                              ),

                              _sectionLabel('COMPANY DETAILS'),
                              _card([
                                TextFormField(
                                  controller: name,
                                  enabled: enabled,
                                  maxLength: 255,
                                  textCapitalization: TextCapitalization.words,
                                  decoration: _decoration(
                                    'Company name',
                                    HugeIcons.strokeRoundedBuilding03,
                                  ),
                                  validator: (value) =>
                                      value == null || value.trim().isEmpty
                                      ? 'Enter the company name'
                                      : null,
                                ),
                              ]),

                              _sectionLabel('CONTACT (OPTIONAL)'),
                              _card([
                                TextFormField(
                                  controller: email,
                                  enabled: enabled,
                                  keyboardType: TextInputType.emailAddress,
                                  autocorrect: false,
                                  decoration: _decoration(
                                    'Company email',
                                    HugeIcons.strokeRoundedMail01,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: phone,
                                  enabled: enabled,
                                  maxLength: 50,
                                  keyboardType: TextInputType.phone,
                                  decoration: _decoration(
                                    'Company phone',
                                    HugeIcons.strokeRoundedCall,
                                  ),
                                ),
                              ]),

                              _sectionLabel('GOOD TO KNOW'),
                              _card([
                                _infoRow(
                                  HugeIcons.strokeRoundedCrown,
                                  'You will be the owner',
                                  'You can invite members and manage the company workspace.',
                                ),
                                _infoRow(
                                  HugeIcons.strokeRoundedShield01,
                                  'No paid plan is activated',
                                  'Creating a company does not start a subscription.',
                                ),
                                _infoRow(
                                  HugeIcons.strokeRoundedFolder01,
                                  'Your records stay put',
                                  'Personal records are not moved, and your current workspace stays selected.',
                                ),
                              ]),

                              if (error != null) _errorBanner(),
                            ],
                          ),
                        ),
                      ),
                      _bottomBar(),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}