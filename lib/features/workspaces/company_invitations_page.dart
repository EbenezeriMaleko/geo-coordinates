import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../auth/providers/auth_provider.dart';
import 'workspace_page_style.dart';
import 'workspace_provider.dart';

class CompanyInvitationService {
  Future<List<Map<String, dynamic>>> pending(String token) async {
    final response = await ApiClient.getJson(
      '/company-invitations',
      bearerToken: token,
    );
    if (response.statusCode != 200) {
      throw Exception('Unable to load invitations.');
    }
    final body = jsonDecode(response.body);
    if (body is! Map || body['data'] is! List) {
      throw Exception('Unexpected invitation response.');
    }
    return (body['data'] as List)
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> respond(String token, int id, bool accept) async {
    final response = await ApiClient.postJson(
      '/company-invitations/$id/respond',
      bearerToken: token,
      body: {'response': accept ? 'accepted' : 'declined'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = jsonDecode(response.body);
      throw Exception(
        body is Map
            ? body['message'] ?? 'Unable to respond to invitation.'
            : 'Unable to respond to invitation.',
      );
    }
  }
}

final companyInvitationServiceProvider = Provider<CompanyInvitationService>(
  (ref) => CompanyInvitationService(),
);
final companyInvitationsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final session = ref.watch(authSessionProvider);
      if (!session.isLoggedIn || !session.isVerified) {
        throw Exception('Sign in and verify your email to view invitations.');
      }
      return ref.read(companyInvitationServiceProvider).pending(session.token);
    });

class CompanyInvitationsPage extends ConsumerStatefulWidget {
  const CompanyInvitationsPage({super.key});
  @override
  ConsumerState<CompanyInvitationsPage> createState() =>
      _CompanyInvitationsPageState();
}

class _CompanyInvitationsPageState
    extends ConsumerState<CompanyInvitationsPage> {
  int? busy;
  bool confirming = false;
  String? error;

  Future<void> respond(Map<String, dynamic> invitation, bool accept) async {
    if (busy != null || confirming) return;
    final id = int.tryParse(invitation['id'].toString());
    if (id == null) return;
    final session = ref.read(authSessionProvider);
    if (!session.isLoggedIn || !session.isVerified) return;
    final company = invitation['company'] is Map
        ? invitation['company']['name']?.toString() ?? 'this company'
        : 'this company';
    bool? confirmed;
    confirming = true;
    try {
      confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(accept ? 'Join $company?' : 'Decline invitation?'),
          content: Text(
            accept
                ? 'You will join as ${companyRoleLabel(invitation['role']?.toString())}. Your active workspace will stay unchanged.'
                : 'You will not join $company. A manager can invite you again later.',
          ),
          actions: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(
                    accept ? 'Accept invitation' : 'Decline invitation',
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ),
      );
    } finally {
      confirming = false;
    }
    if (!mounted ||
        confirmed != true ||
        session.token != ref.read(authSessionProvider).token ||
        !ref.read(authSessionProvider).isVerified) {
      return;
    }
    setState(() {
      busy = id;
      error = null;
    });
    try {
      await ref
          .read(companyInvitationServiceProvider)
          .respond(session.token, id, accept);
      if (!mounted || session.token != ref.read(authSessionProvider).token) {
        return;
      }
      ref.invalidate(companyInvitationsProvider);
      if (accept) await ref.read(workspaceProvider.notifier).refresh();
      if (!mounted || session.token != ref.read(authSessionProvider).token) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? 'Invitation accepted. Use the workspace selector to view your available companies.'
                : 'Invitation declined.',
          ),
        ),
      );
    } catch (failure) {
      if (mounted && session.token == ref.read(authSessionProvider).token) {
        setState(
          () => error = failure.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final invitations = ref.watch(companyInvitationsProvider);
    Future<void> refresh() async {
      ref.invalidate(companyInvitationsProvider);
      try {
        await ref.read(companyInvitationsProvider.future);
      } catch (_) {}
    }

    return PopScope(
      canPop: busy == null,
      child: WorkspaceScaffold(
        appBar: AppBar(
          title: const Text('Company invitations'),
          actions: [
            IconButton(
              tooltip: 'Refresh invitations',
              onPressed: busy == null ? refresh : null,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: invitations.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: TextButton.icon(
              onPressed: refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Unable to load invitations. Retry'),
            ),
          ),
          data: (items) => RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        Icon(Icons.mail_outline, size: 32),
                        SizedBox(height: 12),
                        Text('No pending invitations.'),
                      ],
                    ),
                  ),
                for (final item in items) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.business_outlined),
                    title: Text(
                      item['company'] is Map
                          ? item['company']['name']?.toString() ?? 'Company'
                          : 'Company',
                    ),
                    subtitle: Text(companyRoleLabel(item['role']?.toString())),
                  ),
                  if (item['inviter'] is Map)
                    Text(
                      'Invited by ${item['inviter']['name'] ?? 'a company manager'}',
                    ),
                  if (DateTime.tryParse(item['expires_at']?.toString() ?? '')
                      case final DateTime date)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Expires ${MaterialLocalizations.of(context).formatMediumDate(date.toLocal())}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: busy == null ? () => respond(item, true) : null,
                    icon: const Icon(Icons.check, size: 18),
                    label: Text(
                      busy == item['id'] ? 'Saving...' : 'Accept invitation',
                    ),
                  ),
                  TextButton(
                    onPressed: busy == null ? () => respond(item, false) : null,
                    child: const Text('Decline'),
                  ),
                  const Divider(height: 32),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
