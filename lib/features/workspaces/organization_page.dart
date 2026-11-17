import '../widget/plan_access_lock.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../core/network/api_client.dart';
import '../auth/providers/auth_provider.dart';
import '../widget/app_backarrow.dart'; // adjust to your file name/path
import 'workspace_provider.dart';
import 'workspace_page_style.dart';
import '../subscriptions/entitlement_provider.dart';
import 'team_member_picker.dart';

const Color _accent = Color(0xFF001F3F); // company accent
const Color _pageBackground = Color(0xFFF7F7F8);
const Color _cardBorder = Color(0xFFE8ECF0);
const Color _fieldFill = Color(0xFFF7F7F8);
const Color _amber = Color(0xFFB26A00);
const Color _amberSoft = Color(0xFFFFF4E0);
const Color _green = Color(0xFF1B7F4B);
const Color _greenSoft = Color(0xFFE6F5EC);
const Color _greySoft = Color(0xFFF1F3F5);

typedef OrganizationQuery = ({
  String kind,
  String search,
  String status,
  int page,
  int? team,
});

final organizationPageProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, OrganizationQuery>((ref, query) async {
      final workspace = ref.watch(workspaceProvider);
      final session = ref.watch(authSessionProvider);
      if (workspace.activeCompanyId == null ||
          workspace.isLoading ||
          !session.isVerified) {
        throw Exception('Select an available company workspace.');
      }
      final response = await ApiClient.getJson(
        query.team == null
            ? '/organization/${query.kind}'
            : '/organization/teams/${query.team}/members',
        bearerToken: session.token,
        queryParameters: {
          'page': query.page,
          if (query.team == null) ...{
            'search': query.search,
            'status': query.status,
          },
        },
        tag: 'organization_read',
      );
      if (response.statusCode == 503) {
        throw Exception(
          'Projects and teams are not available on this server yet.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Unable to load company information. Please retry.');
      }
      final body = jsonDecode(response.body);
      if (body is! Map || body['data'] is! Map) {
        throw Exception('Unexpected server response.');
      }
      return Map<String, dynamic>.from(body['data'] as Map);
    });

class OrganizationPage extends ConsumerStatefulWidget {
  const OrganizationPage({super.key, this.teamId, this.teamName});
  final int? teamId;
  final String? teamName;
  @override
  ConsumerState<OrganizationPage> createState() => _OrganizationPageState();
}

class _OrganizationPageState extends ConsumerState<OrganizationPage> {
  String kind = 'projects';
  String search = '';
  String status = 'active';
  int page = 1;
  Timer? debounce;
  final controller = TextEditingController();
  bool removingMember = false;

  // ── Logic (unchanged apart from the confirmation UI) ──────────

  Future<void> setTeamLeader(OrganizationQuery query, int? membershipId) async {
    final company = ref.read(workspaceProvider).activeCompanyId;
    final token = ref.read(authSessionProvider).token;
    if (company == null || widget.teamId == null || removingMember) return;
    setState(() => removingMember = true);
    try {
      if (company != ref.read(workspaceProvider).activeCompanyId ||
          token != ref.read(authSessionProvider).token) {
        throw Exception('Workspace or session changed. Please retry.');
      }
      final response = await ApiClient.patchJson(
        '/organization/teams/${widget.teamId}',
        bearerToken: token,
        body: {'leader_membership_id': membershipId},
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = jsonDecode(response.body);
        throw Exception(
          body is Map
              ? body['message'] ?? 'Unable to update team lead.'
              : 'Unable to update team lead.',
        );
      }
      if (!mounted ||
          company != ref.read(workspaceProvider).activeCompanyId ||
          token != ref.read(authSessionProvider).token) {
        return;
      }
      ref.invalidate(organizationPageProvider(query));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Team lead updated.')));
    } catch (failure) {
      if (mounted &&
          company == ref.read(workspaceProvider).activeCompanyId &&
          token == ref.read(authSessionProvider).token) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(failure.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => removingMember = false);
    }
  }

  Future<void> removeMember(OrganizationQuery query, Map member) async {
    final company = ref.read(workspaceProvider).activeCompanyId;
    final token = ref.read(authSessionProvider).token;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ConfirmSheet(
        icon: HugeIcons.strokeRoundedUserRemove01,
        destructive: true,
        title: 'Remove team member?',
        body:
            '${member['name'] ?? 'This member'} will leave this team. Their company membership and records stay unchanged.',
        confirmLabel: 'Remove from team',
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => removingMember = true);
    try {
      if (company != ref.read(workspaceProvider).activeCompanyId ||
          token != ref.read(authSessionProvider).token) {
        throw Exception('Workspace or session changed. Please retry.');
      }
      final response = await ApiClient.deleteJson(
        '/organization/teams/${widget.teamId}/members/${member['id']}',
        bearerToken: token,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Unable to remove this member. Refresh and check company access.',
        );
      }
      if (!mounted) return;
      ref.invalidate(organizationPageProvider(query));
      setState(() => page = 1);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Member removed from team.')),
      );
    } catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(failure.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => removingMember = false);
    }
  }

  InputDecoration _fieldDecoration(String label) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: c, width: w),
    );
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: _fieldFill,
      labelStyle: const TextStyle(fontSize: 14, color: Colors.black54),
      floatingLabelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: _accent,
      ),
      border: border(_cardBorder),
      enabledBorder: border(_cardBorder),
      focusedBorder: border(_accent, 1.6),
      errorBorder: border(Colors.red.shade400),
      focusedErrorBorder: border(Colors.red.shade400, 1.6),
    );
  }

  Future<void> editItem(
    OrganizationQuery query, {
    Map? item,
    bool? archive,
  }) async {
    final company = ref.read(workspaceProvider).activeCompanyId;
    final token = ref.read(authSessionProvider).token;
    final name = TextEditingController(text: item?['name']?.toString() ?? '');
    final description = TextEditingController(
      text: item?['description']?.toString() ?? '',
    );
    var busy = false;
    String? error;
    final form = GlobalKey<FormState>();
    final navigator = Navigator.of(context, rootNavigator: true);
    final isProject = query.kind == 'projects';
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) {
          final title = archive != null
              ? (archive ? 'Archive item?' : 'Reactivate item?')
              : '${item == null ? 'Create' : 'Edit'} ${isProject ? 'project' : 'team'}';
          final dynamic icon = archive != null
              ? (archive
                    ? HugeIcons.strokeRoundedArchive
                    : HugeIcons.strokeRoundedRefresh)
              : (isProject
                    ? HugeIcons.strokeRoundedFolder01
                    : HugeIcons.strokeRoundedUserGroup);
          return PopScope(
            canPop: !busy,
            child: Dialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: _accent.withValues(alpha: 0.10),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: HugeIcon(icon: icon, color: _accent, size: 24),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (archive == null) ...[
                        TextFormField(
                          controller: name,
                          autofocus: true,
                          maxLength: 150,
                          decoration: _fieldDecoration(
                            'Name',
                          ).copyWith(counterText: ''),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Enter a name'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: description,
                          maxLength: 5000,
                          minLines: 2,
                          maxLines: 5,
                          decoration: _fieldDecoration(
                            'Description (optional)',
                          ).copyWith(counterText: ''),
                        ),
                      ] else
                        Text(
                          archive
                              ? 'Existing records will remain unchanged.'
                              : 'Reactivation is subject to the current plan allowance.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13.5,
                            height: 1.45,
                            color: Colors.black54,
                          ),
                        ),
                      if (error != null)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(top: 14),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.error.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            error!,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: _accent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: busy
                              ? null
                              : () async {
                                  if (!form.currentState!.validate()) return;
                                  update(() {
                                    busy = true;
                                    error = null;
                                  });
                                  try {
                                    if (company !=
                                            ref
                                                .read(workspaceProvider)
                                                .activeCompanyId ||
                                        token !=
                                            ref
                                                .read(authSessionProvider)
                                                .token) {
                                      throw Exception(
                                        'Workspace or session changed. Close and try again.',
                                      );
                                    }
                                    final payload = archive == null
                                        ? <String, dynamic>{
                                            'name': name.text.trim(),
                                            'description': description.text
                                                .trim(),
                                          }
                                        : <String, dynamic>{
                                            'archived': archive,
                                          };
                                    final response = item == null
                                        ? await ApiClient.postJson(
                                            '/organization/${query.kind}',
                                            body: payload,
                                            bearerToken: token,
                                          )
                                        : await ApiClient.patchJson(
                                            '/organization/${query.kind}/${item['id']}',
                                            body: payload,
                                            bearerToken: token,
                                          );
                                    if (response.statusCode < 200 ||
                                        response.statusCode >= 300) {
                                      final body = jsonDecode(response.body);
                                      throw Exception(
                                        body is Map
                                            ? body['message'] ??
                                                  'Unable to save.'
                                            : 'Unable to save.',
                                      );
                                    }
                                    if (!mounted || !dialogContext.mounted) {
                                      return;
                                    }
                                    ref.invalidate(
                                      organizationPageProvider(query),
                                    );
                                    Navigator.pop(dialogContext);
                                  } catch (failure) {
                                    if (dialogContext.mounted) {
                                      update(() {
                                        error = failure.toString().replaceFirst(
                                          'Exception: ',
                                          '',
                                        );
                                        busy = false;
                                      });
                                    }
                                  }
                                },
                          child: Text(
                            busy
                                ? 'Saving...'
                                : archive != null
                                ? 'Confirm'
                                : 'Save',
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: busy
                              ? null
                              : () => Navigator.pop(dialogContext),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.black54,
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
        },
      ),
    );
    await navigator.push(route);
    // A pop resolves before the closing animation removes the form's fields.
    await route.completed;
    name.dispose();
    description.dispose();
  }

  @override
  void dispose() {
    debounce?.cancel();
    controller.dispose();
    super.dispose();
  }

  // ── UI helpers ────────────────────────────────────────────────

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    return parts[0][0].toUpperCase();
  }

  Widget _chip(String text, Color fg, Color bg, {dynamic icon}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          HugeIcon(icon: icon, color: fg, size: 12),
          const SizedBox(width: 4),
        ],
        Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: fg,
          ),
        ),
      ],
    ),
  );

  Widget _segment(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? _accent : Colors.black54,
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = status == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() {
          status = value;
          page = 1;
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? _accent : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? _accent : _cardBorder),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : Colors.black54,
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconAction({
    required dynamic icon,
    required String tooltip,
    required VoidCallback? onPressed,
    Color color = _accent,
  }) {
    final enabled = onPressed != null;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Material(
        color: (enabled ? color : Colors.black26).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onPressed,
          child: Tooltip(
            message: tooltip,
            child: SizedBox(
              width: 38,
              height: 38,
              child: Center(
                child: HugeIcon(
                  icon: icon,
                  color: enabled ? color : Colors.black26,
                  size: 18,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cardShell({required Widget child, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _cardBorder),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  /// Project or team row (when not viewing a single team's members).
  Widget _listItemCard(
    Map item,
    Map<String, dynamic> data,
    OrganizationQuery query,
    bool mayWrite,
    bool mayReduce,
  ) {
    final archived = item['archived_at'] != null;
    final isTeam = kind == 'teams';
    final canWrite = data['can_write'] == true && mayWrite;
    final canManage = data['can_manage'] == true && mayReduce;
    final description = item['description']?.toString();

    Widget? trailing;
    if (canManage) {
      trailing = PopupMenuButton<String>(
        tooltip: 'Manage item',
        icon: const HugeIcon(
          icon: HugeIcons.strokeRoundedMoreVertical,
          color: Colors.black54,
          size: 22,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onSelected: (action) => editItem(
          query,
          item: item,
          archive: action == 'edit' ? null : !archived,
        ),
        itemBuilder: (_) => [
          if (canWrite)
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedEdit02,
                    color: Colors.black87,
                    size: 20,
                  ),
                  SizedBox(width: 12),
                  Text('Edit'),
                ],
              ),
            ),
          if (!archived || canWrite)
            PopupMenuItem(
              value: 'archive',
              child: Row(
                children: [
                  HugeIcon(
                    icon: archived
                        ? HugeIcons.strokeRoundedRefresh
                        : HugeIcons.strokeRoundedArchive,
                    color: Colors.black87,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(archived ? 'Reactivate' : 'Archive'),
                ],
              ),
            ),
        ],
      );
    } else if (isTeam) {
      trailing = const Icon(
        Icons.chevron_right_rounded,
        size: 22,
        color: Colors.black26,
      );
    }

    return _cardShell(
      onTap: isTeam
          ? () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => OrganizationPage(
                  teamId: (item['id'] as num).toInt(),
                  teamName: item['name']?.toString(),
                ),
              ),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: archived ? 0.05 : 0.10),
              borderRadius: BorderRadius.circular(13),
            ),
            alignment: Alignment.center,
            child: HugeIcon(
              icon: isTeam
                  ? HugeIcons.strokeRoundedUserGroup
                  : HugeIcons.strokeRoundedFolder01,
              color: archived ? Colors.black38 : _accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name']?.toString() ?? 'Unnamed',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: archived ? Colors.black54 : Colors.black87,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    archived
                        ? _chip('Archived', Colors.black54, _greySoft)
                        : _chip('Active', _green, _greenSoft),
                    if (isTeam)
                      _chip(
                        '${item['members_count'] ?? 0} members',
                        _accent,
                        _accent.withValues(alpha: 0.10),
                        icon: HugeIcons.strokeRoundedUser,
                      ),
                  ],
                ),
                if (description != null && description.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  /// A member of the team currently being viewed.
  Widget _teamMemberCard(
    Map item,
    Map<String, dynamic> data,
    OrganizationQuery query,
    bool mayWrite,
    bool mayReduce,
  ) {
    final name = item['name']?.toString() ?? 'Unnamed';
    final email = item['email']?.toString() ?? '';
    final leaderId = (data['team'] as Map?)?['leader_membership_id'];
    final isLead = leaderId == item['id'];
    final inactive = item['active'] == false;
    final canWrite = data['can_write'] == true && mayWrite;
    final canManage = data['can_manage'] == true && mayReduce;

    return _cardShell(
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: isLead ? _accent : _accent.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              _initials(name),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: isLead ? Colors.white : _accent,
              ),
            ),
          ),
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
                if (isLead || inactive) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (isLead)
                        _chip(
                          'Team lead',
                          _amber,
                          _amberSoft,
                          icon: HugeIcons.strokeRoundedStar,
                        ),
                      if (inactive)
                        _chip('Inactive', Colors.black54, _greySoft),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (canManage) ...[
            if (canWrite)
              _iconAction(
                icon: HugeIcons.strokeRoundedStar,
                tooltip: isLead ? 'Remove team lead' : 'Set team lead',
                color: isLead ? _amber : _accent,
                onPressed: removingMember || (inactive && !isLead)
                    ? null
                    : () => setTeamLeader(
                        query,
                        isLead ? null : (item['id'] as num).toInt(),
                      ),
              ),
            _iconAction(
              icon: HugeIcons.strokeRoundedUserRemove01,
              tooltip: 'Remove from team',
              color: Theme.of(context).colorScheme.error,
              onPressed: removingMember
                  ? null
                  : () => removeMember(query, item),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyState() {
    final searching = widget.teamId == null && search.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: HugeIcon(
              icon: searching
                  ? HugeIcons.strokeRoundedSearch01
                  : widget.teamId != null || kind == 'teams'
                  ? HugeIcons.strokeRoundedUserGroup
                  : HugeIcons.strokeRoundedFolder01,
              color: _accent,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No results found',
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pager(int last) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _cardBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Previous page',
                onPressed: page > 1 ? () => setState(() => page--) : null,
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedArrowLeft01,
                  color: Colors.black87,
                  size: 22,
                ),
              ),
              Flexible(
                child: Text(
                  'Page $page of $last',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next page',
                onPressed: page < last ? () => setState(() => page++) : null,
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedArrowRight01,
                  color: Colors.black87,
                  size: 22,
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
    final baseTheme = Theme.of(context);
    final permissions =
        ref.watch(workspacePermissionsProvider).asData?.value ??
        const <String, bool>{};
    final mayWrite = permissions['organization.manage'] == true;
    final mayReduce = permissions['organization.reduce'] == true;
    ref.listen(workspaceProvider.select((s) => s.activeCompanyId), (_, _) {
      debounce?.cancel();
      controller.clear();
      setState(() {
        page = 1;
        search = '';
      });
      if (widget.teamId != null && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
    final query = (
      kind: kind,
      search: search,
      status: status,
      page: page,
      team: widget.teamId,
    );
    final response = workspace.activeCompanyId == null
        ? null
        : ref.watch(organizationPageProvider(query));
    Future<void> refresh() async {
      ref.invalidate(organizationPageProvider(query));
      try {
        await ref.read(organizationPageProvider(query).future);
      } catch (_) {}
    }

    return Theme(
      data: baseTheme.copyWith(
        colorScheme: baseTheme.colorScheme.copyWith(primary: _accent),
      ),
      child: WorkspaceScaffold(
        company: workspace.activeCompanyId != null,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          leading: const AppBackButton(),
          title: Text(
            widget.teamName ?? 'Projects & Teams',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: workspace.activeCompanyId == null ? null : refresh,
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedRefresh,
                color: workspace.activeCompanyId == null
                    ? Colors.black26
                    : Colors.black87,
                size: 22,
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: ColoredBox(
          color: _pageBackground,
          child: SafeArea(
            child: workspace.activeCompanyId == null
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          HugeIcon(
                            icon: HugeIcons.strokeRoundedFolder01,
                            color: Colors.black26,
                            size: 40,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Select a company from your Profile to view projects and teams.',
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
                      // Header
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.business_outlined,
                                  size: 16,
                                  color: _accent,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    workspace.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: _accent,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (widget.teamId == null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: _greySoft,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    _segment(
                                      'Projects',
                                      kind == 'projects',
                                      () => setState(() {
                                        kind = 'projects';
                                        page = 1;
                                      }),
                                    ),
                                    _segment(
                                      'Teams',
                                      kind == 'teams',
                                      () => setState(() {
                                        kind = 'teams';
                                        page = 1;
                                      }),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: controller,
                                decoration: InputDecoration(
                                  hintText: 'Search $kind',
                                  hintStyle: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.black45,
                                  ),
                                  filled: true,
                                  fillColor: _fieldFill,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  prefixIcon: const Padding(
                                    padding: EdgeInsets.all(14),
                                    child: HugeIcon(
                                      icon: HugeIcons.strokeRoundedSearch01,
                                      color: Colors.black45,
                                      size: 20,
                                    ),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: _cardBorder,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: _cardBorder,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: _accent,
                                      width: 1.6,
                                    ),
                                  ),
                                ),
                                onChanged: (value) {
                                  debounce?.cancel();
                                  debounce = Timer(
                                    const Duration(milliseconds: 350),
                                    () {
                                      if (mounted) {
                                        setState(() {
                                          search = value.trim();
                                          page = 1;
                                        });
                                      }
                                    },
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    _filterChip('Active', 'active'),
                                    _filterChip('Archived', 'archived'),
                                    _filterChip('All statuses', 'all'),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: _cardBorder),
                      Expanded(
                        child: response!.when(
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (error, _) => Center(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const HugeIcon(
                                    icon: HugeIcons.strokeRoundedWifiOff01,
                                    color: Colors.black26,
                                    size: 40,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    error.toString().replaceFirst(
                                      'Exception: ',
                                      '',
                                    ),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      height: 1.4,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  FilledButton.tonal(
                                    onPressed: refresh,
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          data: (data) {
                            final pagination =
                                data[widget.teamId == null
                                        ? 'items'
                                        : 'members']
                                    as Map? ??
                                {};
                            final items = (pagination['data'] as List? ?? [])
                                .whereType<Map>()
                                .toList();
                            final last =
                                (pagination['last_page'] as num?)?.toInt() ?? 1;
                            final canWrite =
                                data['can_write'] == true && mayWrite;
                            final total =
                                (pagination['total'] as num?)?.toInt() ??
                                items.length;
                            final noun = widget.teamId != null
                                ? (total == 1 ? 'member' : 'members')
                                : kind == 'teams'
                                ? (total == 1 ? 'team' : 'teams')
                                : (total == 1 ? 'project' : 'projects');

                            return Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    12,
                                    16,
                                    0,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '$total $noun',
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black54,
                                          ),
                                        ),
                                      ),
                                      if (canWrite ||
                                          ref
                                                  .watch(
                                                    workspacePermissionsProvider,
                                                  )
                                                  .asData
                                                  ?.value['organization.manage'] ==
                                              false)
                                        PlanAccessLock(
                                          locked: !canWrite,
                                          child: FilledButton.icon(
                                            onPressed: widget.teamId != null
                                                ? () => Navigator.of(context).push(
                                                    MaterialPageRoute<void>(
                                                      builder: (_) =>
                                                          TeamMemberPicker(
                                                            team:
                                                                widget.teamId!,
                                                            onAdded: () =>
                                                                ref.invalidate(
                                                                  organizationPageProvider(
                                                                    query,
                                                                  ),
                                                                ),
                                                          ),
                                                    ),
                                                  )
                                                : () => editItem(query),
                                            style: FilledButton.styleFrom(
                                              backgroundColor: _accent,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 14,
                                                    vertical: 10,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                            ),
                                            icon: HugeIcon(
                                              icon: widget.teamId != null
                                                  ? HugeIcons
                                                        .strokeRoundedUserAdd01
                                                  : HugeIcons
                                                        .strokeRoundedAddCircle,
                                              color: Colors.white,
                                              size: 18,
                                            ),
                                            label: Text(
                                              widget.teamId != null
                                                  ? 'Add member'
                                                  : kind == 'projects'
                                                  ? 'New project'
                                                  : 'New team',
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: RefreshIndicator(
                                    onRefresh: refresh,
                                    child: ListView(
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        12,
                                        16,
                                        24,
                                      ),
                                      children: [
                                        if (items.isEmpty)
                                          _emptyState()
                                        else
                                          for (final item in items)
                                            widget.teamId != null
                                                ? _teamMemberCard(
                                                    item,
                                                    data,
                                                    query,
                                                    mayWrite,
                                                    mayReduce,
                                                  )
                                                : _listItemCard(
                                                    item,
                                                    data,
                                                    query,
                                                    mayWrite,
                                                    mayReduce,
                                                  ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (last > 1) _pager(last),
                              ],
                            );
                          },
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

// ── Confirmation sheet ─────────────────────────────────────────────

class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({
    required this.icon,
    required this.title,
    required this.body,
    required this.confirmLabel,
    this.destructive = false,
  });

  final dynamic icon;
  final String title;
  final String body;
  final String confirmLabel;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Theme.of(context).colorScheme.error : _accent;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD5DCE5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: HugeIcon(icon: icon, color: color, size: 26),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: color,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  confirmLabel,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
