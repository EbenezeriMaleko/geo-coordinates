import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../core/network/api_client.dart';
import '../auth/providers/auth_provider.dart';
import '../subscriptions/entitlement_provider.dart';
import '../widget/app_backarrow.dart'; // adjust to your file name/path
import 'workspace_provider.dart';
import 'workspace_page_style.dart';

const Color _accent = Color(0xFF197568); // company accent
const Color _pageBackground = Color(0xFFF7F7F8);
const Color _cardBorder = Color(0xFFE8ECF0);
const Color _fieldFill = Color(0xFFF7F7F8);
const Color _amber = Color(0xFFB26A00);
const Color _amberSoft = Color(0xFFFFF4E0);

bool validInvitationEmail(String value) {
  final email = value.trim();
  return email.length <= 255 &&
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
}

List<String> parseCompanyInvitationRoles(dynamic raw) => raw is List
    ? raw
          .whereType<String>()
          .where(
            const [
              'admin',
              'employee',
              'field_operator',
              'reviewer',
              'viewer',
            ].contains,
          )
          .toSet()
          .toList()
    : [];

class CompanyInviteService {
  Future<bool?> inviteEmail(
    String token,
    int company,
    String email,
    String role,
  ) async {
    final response = await ApiClient.postJson(
      '/companies/$company/invitations',
      bearerToken: token,
      body: {'email': email.trim(), 'role': role},
    );
    final body = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errors = body is Map ? body['errors'] : null;
      final messages = errors is Map
          ? errors.values
                .whereType<List>()
                .expand((v) => v)
                .whereType<String>()
                .toList()
          : <String>[];
      throw Exception(
        messages.isNotEmpty
            ? messages.first
            : body is Map
            ? body['message'] ?? 'Unable to create invitation.'
            : 'Unable to create invitation.',
      );
    }
    final data = body is Map ? body['data'] : null;
    return data is Map && data['email_delivered'] is bool
        ? data['email_delivered'] as bool
        : null;
  }

  Future<Map<String, dynamic>> get(
    String path,
    String token, {
    Map<String, dynamic>? query,
  }) async {
    final response = await ApiClient.getJson(
      path,
      bearerToken: token,
      queryParameters: query,
    );
    final body = jsonDecode(response.body);
    if (response.statusCode != 200 || body is! Map) {
      throw Exception('Unable to load invitation options.');
    }
    return Map<String, dynamic>.from(body);
  }

  Future<List<String>> roles(String token, int company) async =>
      parseCompanyInvitationRoles(
        (await get('/companies/$company/members', token))['assignable_roles'],
      );

  Future<List<Map<String, dynamic>>> search(
    String token,
    int company,
    String query,
  ) async {
    final body = await get(
      '/companies/$company/users',
      token,
      query: {'query': query},
    );
    if (body['data'] is! List) {
      throw Exception('Unexpected account search response.');
    }
    return (body['data'] as List)
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<bool?> invite(String token, int company, int user, String role) async {
    final response = await ApiClient.postJson(
      '/companies/$company/invitations',
      bearerToken: token,
      body: {'user_id': user, 'role': role},
    );
    final body = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        body is Map
            ? body['message'] ?? 'Unable to create invitation.'
            : 'Unable to create invitation.',
      );
    }
    final data = body is Map ? body['data'] : null;
    return data is Map && data['email_delivered'] is bool
        ? data['email_delivered'] as bool
        : null;
  }
}

final companyInviteServiceProvider = Provider<CompanyInviteService>(
  (ref) => CompanyInviteService(),
);
final companyInviteRolesProvider = FutureProvider.autoDispose
    .family<List<String>, int>((ref, company) async {
      final session = ref.watch(authSessionProvider);
      final workspace = ref.watch(workspaceProvider);
      if (!session.isVerified ||
          !session.isLoggedIn ||
          workspace.activeCompanyId != company ||
          !canViewCompanyDirectory(workspace, session.user?.role)) {
        throw Exception('Company access changed.');
      }
      return ref
          .read(companyInviteServiceProvider)
          .roles(session.token, company);
    });
typedef InviteSearchQuery = ({int company, String search});
final companyInviteSearchProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, InviteSearchQuery>((ref, query) async {
      final session = ref.watch(authSessionProvider);
      final workspace = ref.watch(workspaceProvider);
      if (!session.isVerified ||
          !session.isLoggedIn ||
          workspace.activeCompanyId != query.company ||
          !canViewCompanyDirectory(workspace, session.user?.role)) {
        throw Exception('Company access changed.');
      }
      if (query.search.length < 2) return [];
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!ref.mounted) return [];
      return ref
          .read(companyInviteServiceProvider)
          .search(session.token, query.company, query.search);
    });

class CompanyInviteForm extends ConsumerStatefulWidget {
  const CompanyInviteForm({super.key, required this.company});
  final int company;
  @override
  ConsumerState<CompanyInviteForm> createState() => _CompanyInviteFormState();
}

class _CompanyInviteFormState extends ConsumerState<CompanyInviteForm> {
  String search = '';
  Map<String, dynamic>? selected;
  String? role;
  String? error;
  bool busy = false;

  // ── Logic (unchanged) ─────────────────────────────────────────

  Future<void> send(List<String> roles, String selectedRole) async {
    if (busy || selected == null || !roles.contains(selectedRole)) return;
    final user = int.tryParse(selected!['id'].toString());
    final email = selected!['email']?.toString().trim() ?? '';
    if (user == null && !validInvitationEmail(email)) return;
    final session = ref.read(authSessionProvider);
    final workspace = ref.read(workspaceProvider);
    if (!session.isLoggedIn ||
        !session.isVerified ||
        workspace.activeCompanyId != widget.company ||
        !canViewCompanyDirectory(workspace, session.user?.role) ||
        ref
                .read(entitlementProvider)
                .asData
                ?.value['company.employee_management']
                ?.allowed !=
            true) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final delivered = user == null
          ? await ref
                .read(companyInviteServiceProvider)
                .inviteEmail(session.token, widget.company, email, selectedRole)
          : await ref
                .read(companyInviteServiceProvider)
                .invite(session.token, widget.company, user, selectedRole);
      if (!mounted ||
          session.token != ref.read(authSessionProvider).token ||
          widget.company != ref.read(workspaceProvider).activeCompanyId) {
        return;
      }
      Navigator.pop(
        context,
        delivered == true
            ? 'Invitation created and email delivered.'
            : delivered == false
            ? 'Invitation created. Email delivery failed; ask the recipient to register or sign in with the invited email and check invitations.'
            : 'Invitation created. Email delivery is not confirmed.',
      );
    } catch (failure) {
      if (mounted &&
          session.token == ref.read(authSessionProvider).token &&
          widget.company == ref.read(workspaceProvider).activeCompanyId) {
        setState(
          () => error = failure.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // ── UI helpers ────────────────────────────────────────────────

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    return parts[0][0].toUpperCase();
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

  Widget _card(Widget child, {Color? border, double borderWidth = 1}) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border ?? _cardBorder, width: borderWidth),
        ),
        child: child,
      );

  Widget _avatar(String name, {double size = 42}) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: _accent.withValues(alpha: 0.10),
      shape: BoxShape.circle,
    ),
    alignment: Alignment.center,
    child: Text(
      _initials(name),
      style: TextStyle(
        fontSize: size * 0.36,
        fontWeight: FontWeight.w800,
        color: _accent,
      ),
    ),
  );

  Widget _notice({
    required dynamic icon,
    required String text,
    bool isError = false,
    Widget? action,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final color = isError ? scheme.error : _amber;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isError ? scheme.error.withValues(alpha: 0.08) : _amberSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HugeIcon(icon: icon, color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                    color: isError ? scheme.error : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          if (action != null) ...[const SizedBox(height: 8), action],
        ],
      ),
    );
  }

  OutlineInputBorder _border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );

  Widget _userRow(Map<String, dynamic> user, {required VoidCallback? onTap}) {
    final name = user['name']?.toString() ?? 'Account';
    final email = user['email']?.toString() ?? '';
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Row(
          children: [
            _avatar(name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  if (email.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const HugeIcon(
              icon: HugeIcons.strokeRoundedAddCircle,
              color: _accent,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _roleOption(String value, String? current, bool enabled) {
    final isSelected = value == current;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? () => setState(() => role = value) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: isSelected
                ? _accent.withValues(alpha: 0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? _accent : _cardBorder,
              width: isSelected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? _accent : Colors.black26,
                    width: 2,
                  ),
                ),
                alignment: Alignment.center,
                child: isSelected
                    ? Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: _accent,
                          shape: BoxShape.circle,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  companyRoleLabel(value),
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: enabled ? Colors.black87 : Colors.black38,
                  ),
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
    final workspace = ref.watch(workspaceProvider);
    final session = ref.watch(authSessionProvider);
    final baseTheme = Theme.of(context);
    final available =
        session.isLoggedIn &&
        session.isVerified &&
        workspace.activeCompanyId == widget.company &&
        canViewCompanyDirectory(workspace, session.user?.role);
    final access = ref.watch(entitlementProvider);
    final allowed =
        available &&
        access.asData?.value['company.employee_management']?.allowed == true;
    final options = available
        ? ref.watch(companyInviteRolesProvider(widget.company))
        : null;
    final roles = options?.asData?.value ?? <String>[];
    final selectedRole = roles.contains(role) ? role : roles.firstOrNull;
    final query = (company: widget.company, search: search);
    final results = allowed && search.length >= 2 && selected == null
        ? ref.watch(companyInviteSearchProvider(query))
        : null;
    final canSend =
        allowed && !busy && selected != null && selectedRole != null;

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
              'Invite company member',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            centerTitle: true,
          ),
          body: ColoredBox(
            color: _pageBackground,
            child: !available
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          HugeIcon(
                            icon: HugeIcons.strokeRoundedShield01,
                            color: Colors.black26,
                            size: 40,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Company or session changed. Reopen the invitation form.',
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
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                          children: [
                            // Workspace chip
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: _accent.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.business_outlined,
                                      size: 15,
                                      color: _accent,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        workspace.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: _accent,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            if (!allowed)
                              _notice(
                                icon: HugeIcons.strokeRoundedAlert02,
                                text: access.isLoading
                                    ? 'Checking invitation access...'
                                    : access.hasError
                                    ? 'Unable to verify invitation access.'
                                    : 'Invitations are not available with your current company access.',
                                action: TextButton(
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(0, 32),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () {
                                    ref.invalidate(entitlementProvider);
                                    ref.invalidate(
                                      workspaceAccessSnapshotProvider,
                                    );
                                  },
                                  child: const Text(
                                    'Refresh access',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: _amber,
                                    ),
                                  ),
                                ),
                              ),

                            // Step 1: account
                            _sectionLabel('ACCOUNT OR EMAIL'),
                            _card(
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  TextField(
                                    enabled: allowed && !busy,
                                    maxLength: 100,
                                    decoration: InputDecoration(
                                      labelText: 'Find account',
                                      hintText: 'Name or email',
                                      counterText: '',
                                      filled: true,
                                      fillColor: _fieldFill,
                                      labelStyle: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.black54,
                                      ),
                                      floatingLabelStyle: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _accent,
                                      ),
                                      prefixIcon: const Padding(
                                        padding: EdgeInsets.all(14),
                                        child: HugeIcon(
                                          icon: HugeIcons.strokeRoundedSearch01,
                                          color: Colors.black45,
                                          size: 20,
                                        ),
                                      ),
                                      border: _border(_cardBorder),
                                      enabledBorder: _border(_cardBorder),
                                      disabledBorder: _border(_cardBorder),
                                      focusedBorder: _border(_accent, 1.6),
                                    ),
                                    onChanged: (value) => setState(() {
                                      search = value.trim();
                                      selected = null;
                                      error = null;
                                    }),
                                  ),
                                  if (selected == null &&
                                      validInvitationEmail(search))
                                    Material(
                                      color: Colors.white,
                                      child: ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: const Icon(
                                          Icons.mail_outline,
                                          color: _accent,
                                        ),
                                        title: const Text('Invite by email'),
                                        subtitle: Text(search),
                                        onTap: allowed && !busy
                                            ? () => setState(
                                                () => selected = {
                                                  'name': search,
                                                  'email': search,
                                                },
                                              )
                                            : null,
                                      ),
                                    ),
                                  if (selected == null && search.length < 2)
                                    const Padding(
                                      padding: EdgeInsets.fromLTRB(4, 10, 4, 0),
                                      child: Text(
                                        'Enter an email address or search for an existing account.',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ),
                                  if (results != null)
                                    results.when(
                                      loading: () => const Padding(
                                        padding: EdgeInsets.all(16),
                                        child: Center(
                                          child: SizedBox.square(
                                            dimension: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.4,
                                            ),
                                          ),
                                        ),
                                      ),
                                      error: (_, _) => Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: TextButton(
                                          onPressed: () => ref.invalidate(
                                            companyInviteSearchProvider(query),
                                          ),
                                          child: const Text(
                                            'Unable to find accounts. Retry',
                                          ),
                                        ),
                                      ),
                                      data: (users) => Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: users.isEmpty
                                            ? const Padding(
                                                padding: EdgeInsets.all(12),
                                                child: Text(
                                                  'No matching accounts.',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: Colors.black54,
                                                  ),
                                                ),
                                              )
                                            : Column(
                                                children: [
                                                  for (final user in users)
                                                    _userRow(
                                                      user,
                                                      onTap: busy
                                                          ? null
                                                          : () => setState(
                                                              () => selected =
                                                                  user,
                                                            ),
                                                    ),
                                                ],
                                              ),
                                      ),
                                    ),
                                ],
                              ),
                            ),

                            if (selected != null && selected!['id'] == null)
                              _notice(
                                icon: HugeIcons.strokeRoundedMail01,
                                text:
                                    'The recipient must register or sign in with ${selected!['email']} to accept the invitation.',
                              ),
                            if (selected != null) ...[
                              const SizedBox(height: 12),
                              _card(
                                Row(
                                  children: [
                                    _avatar(
                                      selected!['name']?.toString() ??
                                          'Selected account',
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'SELECTED',
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.7,
                                              color: _accent,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            selected!['name']?.toString() ??
                                                'Selected account',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.black87,
                                            ),
                                          ),
                                          if ((selected!['email']?.toString() ??
                                                  '')
                                              .isNotEmpty)
                                            Text(
                                              selected!['email'].toString(),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 12.5,
                                                color: Colors.black54,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Clear selected account',
                                      onPressed: busy
                                          ? null
                                          : () =>
                                                setState(() => selected = null),
                                      icon: const HugeIcon(
                                        icon: HugeIcons.strokeRoundedCancel01,
                                        color: Colors.black54,
                                        size: 20,
                                      ),
                                    ),
                                  ],
                                ),
                                border: _accent.withValues(alpha: 0.4),
                                borderWidth: 1.4,
                              ),
                            ],

                            // Step 2: role
                            _sectionLabel('COMPANY ROLE'),
                            if (options?.isLoading == true)
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            else if (options?.hasError == true)
                              _card(
                                Center(
                                  child: TextButton(
                                    onPressed: () => ref.invalidate(
                                      companyInviteRolesProvider(
                                        widget.company,
                                      ),
                                    ),
                                    child: const Text(
                                      'Unable to load roles. Retry',
                                    ),
                                  ),
                                ),
                              )
                            else if (roles.isEmpty)
                              _card(
                                const Text(
                                  'No invitation roles are enabled in the company plan.',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    height: 1.4,
                                    color: Colors.black54,
                                  ),
                                ),
                              )
                            else
                              _card(
                                Column(
                                  children: [
                                    for (final value in roles)
                                      _roleOption(
                                        value,
                                        selectedRole,
                                        allowed && !busy,
                                      ),
                                  ],
                                ),
                              ),

                            if (error != null)
                              _notice(
                                icon: HugeIcons.strokeRoundedAlert02,
                                text: error!,
                                isError: true,
                              ),
                          ],
                        ),
                      ),

                      // Sticky send bar
                      Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          border: Border(top: BorderSide(color: _cardBorder)),
                        ),
                        child: SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (selected != null && selectedRole != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Text(
                                      'Invite ${selected!['name'] ?? 'this account'} as ${companyRoleLabel(selectedRole)}',
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.icon(
                                    onPressed: canSend
                                        ? () => send(roles, selectedRole)
                                        : null,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: _accent,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
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
                                        : HugeIcon(
                                            icon: HugeIcons
                                                .strokeRoundedUserAdd01,
                                            color: canSend
                                                ? Colors.white
                                                : Colors.black38,
                                            size: 18,
                                          ),
                                    label: Text(
                                      busy ? 'Sending...' : 'Send invitation',
                                      style: const TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
