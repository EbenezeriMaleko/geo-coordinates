import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../core/network/api_client.dart';
import '../auth/providers/auth_provider.dart';
import 'workspace_provider.dart';
import 'workspace_page_style.dart';

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

  @override
  Widget build(BuildContext context) {
    ref.watch(authSessionProvider);
    return PopScope(
      canPop: !busy,
      child: WorkspaceScaffold(
        company: true,
        appBar: AppBar(title: const Text('Create company')),
        body: !available
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Sign in with a verified account to create a company. Reopen this form if your account changed.',
                  ),
                ),
              )
            : Form(
                key: form,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      'You will be the company owner.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: name,
                      enabled: !busy && !uncertain,
                      maxLength: 255,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Company name',
                        prefixIcon: Icon(Icons.business_outlined),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Enter the company name'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: email,
                      enabled: !busy && !uncertain,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Company email (optional)',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: phone,
                      enabled: !busy && !uncertain,
                      maxLength: 50,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Company phone (optional)',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Creating a company does not activate a paid plan or move your personal records. Your current workspace will stay selected.',
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    if (uncertain)
                      OutlinedButton.icon(
                        onPressed: busy ? null : checkWorkspaces,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Check workspaces'),
                      )
                    else
                      FilledButton.icon(
                        onPressed: busy ? null : create,
                        icon: const Icon(Icons.add_business_outlined, size: 18),
                        label: Text(busy ? 'Creating...' : 'Create company'),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
