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
import 'team_member_picker.dart';
import 'field_job_link_picker.dart';

const Color _accent = Color(0xFF197568); // company accent
const Color _pageBackground = Color(0xFFF7F7F8);
const Color _cardBorder = Color(0xFFE8ECF0);
const Color _fieldFill = Color(0xFFF7F7F8);
const Color _greySoft = Color(0xFFF1F3F5);

class FieldJobService {
  Future<void> save(
    String token, {
    int? job,
    required Map<String, dynamic> payload,
  }) async {
    final response = job == null
        ? await ApiClient.postJson(
            '/field-jobs',
            bearerToken: token,
            body: payload,
          )
        : await ApiClient.patchJson(
            '/field-jobs/$job',
            bearerToken: token,
            body: payload,
          );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = jsonDecode(response.body);
      throw Exception(
        body is Map
            ? body['message'] ?? 'Unable to save job.'
            : 'Unable to save job.',
      );
    }
  }
}

final fieldJobServiceProvider = Provider<FieldJobService>(
  (ref) => FieldJobService(),
);

class FieldJobForm extends ConsumerStatefulWidget {
  const FieldJobForm({
    super.key,
    required this.workspaceId,
    required this.onSaved,
    this.job,
  });
  final int workspaceId;
  final VoidCallback onSaved;
  final Map? job;
  @override
  ConsumerState<FieldJobForm> createState() => _FieldJobFormState();
}

class _FieldJobFormState extends ConsumerState<FieldJobForm> {
  late final String _tokenAtOpen;
  late final int _companyAtOpen;
  final form = GlobalKey<FormState>();
  final title = TextEditingController();
  final description = TextEditingController();
  String search = '';
  int page = 1;
  int? assignee;
  String? assigneeName;
  int? teamId;
  String? teamName;
  bool assignmentChanged = false;
  int? projectId;
  int? recordId;
  String? projectName;
  String? recordName;
  bool projectChanged = false;
  bool recordChanged = false;
  bool busy = false;
  String? error;
  Timer? debounce;

  // ── Logic (unchanged) ─────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tokenAtOpen = ref.read(authSessionProvider).token;
    _companyAtOpen = widget.workspaceId;
    title.text = widget.job?['title']?.toString() ?? '';
    description.text = widget.job?['description']?.toString() ?? '';
    assignee = (widget.job?['assignee_membership_id'] as num?)?.toInt();
    assigneeName = widget.job?['assignee_name']?.toString();
    teamId = (widget.job?['company_team_id'] as num?)?.toInt();
    teamName = widget.job?['team_name']?.toString();
    projectId = (widget.job?['company_project_id'] as num?)?.toInt();
    recordId = (widget.job?['land_id'] as num?)?.toInt();
    projectName = widget.job?['project_name']?.toString();
    recordName = widget.job?['record_name']?.toString();
  }

  bool get _scopeCurrent {
    if (!mounted) return false;
    final session = ref.read(authSessionProvider);
    return session.isLoggedIn &&
        session.isVerified &&
        session.token == _tokenAtOpen &&
        widget.workspaceId == _companyAtOpen &&
        ref.read(workspaceProvider).activeCompanyId == _companyAtOpen;
  }

  @override
  void dispose() {
    debounce?.cancel();
    title.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !_scopeCurrent || ref.read(workspaceProvider).isLoading) return;
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final session = ref.read(authSessionProvider);
      if (widget.workspaceId != ref.read(workspaceProvider).activeCompanyId ||
          !session.isVerified) {
        throw Exception(
          'Workspace or session changed. Reopen the form and try again.',
        );
      }
      if (widget.job != null &&
          ['completed', 'cancelled'].contains(widget.job!['status'])) {
        throw Exception('This job is closed.');
      }
      final originalStatus = widget.job?['status']?.toString() ?? 'draft';
      if (originalStatus != 'draft' && assignee == null && teamId == null) {
        throw Exception('Assign a member or team before saving this job.');
      }
      final jobId = widget.job == null
          ? null
          : int.tryParse(widget.job!['id'].toString());
      if (widget.job != null && (jobId == null || jobId <= 0)) {
        throw Exception('Invalid job reference. Reopen the form.');
      }
      final payload = {
        'title': title.text.trim(),
        'description': description.text.trim(),
        if (widget.job == null || assignmentChanged)
          'assignee_membership_id': assignee,
        if (widget.job == null || assignmentChanged) 'company_team_id': teamId,
        if (projectChanged) 'company_project_id': projectId,
        if (recordChanged) 'land_id': recordId,
        'status':
            originalStatus == 'draft' && (assignee != null || teamId != null)
            ? 'assigned'
            : originalStatus,
      };
      await ref
          .read(fieldJobServiceProvider)
          .save(_tokenAtOpen, job: jobId, payload: payload);
      if (!mounted || !_scopeCurrent) return;
      widget.onSaved();
      Navigator.pop(context);
    } catch (failure) {
      if (mounted && _scopeCurrent) {
        setState(() {
          error = failure.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pickTeam() async {
    if (!_scopeCurrent || busy) return;
    final item = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => FieldJobLinkPicker(
          company: widget.workspaceId,
          project: false,
          team: true,
        ),
      ),
    );
    if (!mounted || !_scopeCurrent || item == null) return;
    final id = int.tryParse(item['id'].toString());
    if (id == null) return;
    setState(() {
      teamId = id;
      teamName = item['name']?.toString();
      assignee = null;
      assigneeName = null;
      assignmentChanged = true;
    });
  }

  Future<void> pickLink(bool project) async {
    if (!_scopeCurrent || busy) return;
    final token = ref.read(authSessionProvider).token;
    final item = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) =>
            FieldJobLinkPicker(company: widget.workspaceId, project: project),
      ),
    );
    if (!mounted ||
        item == null ||
        !_scopeCurrent ||
        widget.workspaceId != ref.read(workspaceProvider).activeCompanyId ||
        token != ref.read(authSessionProvider).token) {
      return;
    }
    final id = int.tryParse(item['id'].toString());
    if (id == null) return;
    setState(() {
      if (project) {
        projectId = id;
        projectName = item['name']?.toString();
        projectChanged = true;
      } else {
        recordId = id;
        recordName = item['name']?.toString();
        recordChanged = true;
      }
    });
  }

  // ── UI helpers ────────────────────────────────────────────────

  InputDecoration _decoration(String label, {dynamic icon, String? hint}) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: c, width: w),
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
      prefixIcon: icon == null
          ? null
          : Padding(
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

  Widget _card(List<Widget> children, {EdgeInsets? padding}) => Container(
    padding: padding ?? const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _cardBorder),
    ),
    child: Column(children: children),
  );

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    return parts[0][0].toUpperCase();
  }

  /// A tappable row used for project, record, team and assignee.
  Widget _pickRow({
    required dynamic icon,
    required String label,
    required String value,
    String? subtitle,
    bool filled = false,
    VoidCallback? onTap,
    VoidCallback? onClear,
    String clearTooltip = 'Clear',
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: filled ? 0.12 : 0.07),
                borderRadius: BorderRadius.circular(11),
              ),
              alignment: Alignment.center,
              child: HugeIcon(icon: icon, color: _accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: Colors.black45,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: filled ? FontWeight.w700 : FontWeight.w500,
                      color: filled ? Colors.black87 : Colors.black54,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                ],
              ),
            ),
            if (onClear != null)
              IconButton(
                tooltip: clearTooltip,
                onPressed: busy ? null : onClear,
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedCancel01,
                  color: Colors.black54,
                  size: 20,
                ),
              )
            else if (onTap != null)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: Colors.black26,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget linkedItem(bool project) {
    final id = project ? projectId : recordId;
    final name = project ? projectName : recordName;
    return _pickRow(
      icon: project
          ? HugeIcons.strokeRoundedFolder01
          : HugeIcons.strokeRoundedLocation01,
      label: project ? 'Project' : 'Record',
      value: name ?? (id == null ? 'Not linked' : 'Current #$id'),
      filled: id != null,
      onTap: busy ? null : () => pickLink(project),
      clearTooltip: project ? 'Unlink project' : 'Unlink record',
      onClear: id == null
          ? null
          : () => setState(() {
              if (project) {
                projectId = null;
                projectName = null;
                projectChanged = true;
              } else {
                recordId = null;
                recordName = null;
                recordChanged = true;
              }
            }),
    );
  }

  Widget _memberRow(Map member) {
    final name = member['name']?.toString() ?? '';
    final email = member['email']?.toString() ?? '';
    final isSelected = assignee == member['id'];
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: busy
          ? null
          : () => setState(() {
              assignee = (member['id'] as num).toInt();
              assigneeName = member['name']?.toString();
              teamId = null;
              teamName = null;
              assignmentChanged = true;
            }),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected ? _accent.withValues(alpha: 0.06) : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? _accent : Colors.transparent,
            width: 1.4,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                _initials(name),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: _accent,
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
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  if (email.isNotEmpty)
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
              ),
            ),
            if (isSelected)
              Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: _accent,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const HugeIcon(
                  icon: HugeIcons.strokeRoundedTick02,
                  color: Colors.white,
                  size: 14,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
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
              if (error != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedAlert02,
                        color: scheme.error,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          error!,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: scheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: busy ? null : save,
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
                          icon: HugeIcons.strokeRoundedTick02,
                          color: Colors.white,
                          size: 18,
                        ),
                  label: Text(
                    busy
                        ? 'Saving...'
                        : widget.job == null
                        ? 'Create job'
                        : 'Save changes',
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
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authSessionProvider);
    final workspace = ref.watch(workspaceProvider);
    final baseTheme = Theme.of(context);
    final available = _scopeCurrent && !workspace.isLoading;
    final query = (search: search, page: page);
    final results = available && search.length >= 2
        ? ref.watch(memberSearchProvider(query))
        : null;

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
            title: Text(
              widget.job == null ? 'New field job' : 'Edit field job',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
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
                          Text(
                            _scopeCurrent
                                ? 'Workspace access is refreshing. Your form is kept.'
                                : 'Workspace or account changed. Reopen the field job form.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
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
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            children: [
                              // Job details
                              _sectionLabel('JOB DETAILS'),
                              _card([
                                TextFormField(
                                  controller: title,
                                  enabled: !busy,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  maxLength: 150,
                                  decoration: _decoration(
                                    'Job title',
                                    icon: HugeIcons.strokeRoundedTask01,
                                  ),
                                  validator: (value) =>
                                      value == null || value.trim().isEmpty
                                      ? 'Enter a job title'
                                      : null,
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: description,
                                  enabled: !busy,
                                  minLines: 3,
                                  maxLines: 6,
                                  maxLength: 5000,
                                  decoration: _decoration(
                                    'Description (optional)',
                                  ),
                                ),
                              ]),

                              // Project & record
                              _sectionLabel('PROJECT & RECORD'),
                              _card([
                                linkedItem(true),
                                const Divider(
                                  height: 1,
                                  color: Color(0xFFEEF1F4),
                                ),
                                linkedItem(false),
                              ], padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              )),

                              // Assignment
                              _sectionLabel('ASSIGNMENT'),
                              _card([
                                _pickRow(
                                  icon: HugeIcons.strokeRoundedUserGroup,
                                  label: 'Team',
                                  value: teamId == null
                                      ? 'Assign a team'
                                      : (teamName ?? 'Team #$teamId'),
                                  subtitle: teamId == null
                                      ? null
                                      : 'Team assignment',
                                  filled: teamId != null,
                                  onTap: busy ? null : pickTeam,
                                  clearTooltip: 'Clear team',
                                  onClear: teamId == null
                                      ? null
                                      : () => setState(() {
                                          teamId = null;
                                          teamName = null;
                                          assignmentChanged = true;
                                        }),
                                ),
                                const Divider(
                                  height: 1,
                                  color: Color(0xFFEEF1F4),
                                ),
                                _pickRow(
                                  icon: HugeIcons.strokeRoundedUser,
                                  label: 'Member',
                                  value:
                                      assigneeName ??
                                      (teamId == null
                                          ? 'Unassigned'
                                          : 'Assigned to team'),
                                  subtitle: assignee == null && teamId == null
                                      ? 'Draft'
                                      : 'Assigned',
                                  filled: assignee != null,
                                  clearTooltip: 'Clear assignee',
                                  onClear: assignee == null
                                      ? null
                                      : () => setState(() {
                                          assignee = null;
                                          assigneeName = null;
                                          assignmentChanged = true;
                                        }),
                                ),
                              ], padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              )),

                              _sectionLabel('FIND COMPANY MEMBER'),
                              _card([
                                TextField(
                                  enabled: !busy,
                                  decoration: _decoration(
                                    'Find company member',
                                    icon: HugeIcons.strokeRoundedSearch01,
                                    hint: 'Name or email',
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
                                if (results == null)
                                  const Padding(
                                    padding: EdgeInsets.fromLTRB(4, 10, 4, 2),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        'Type at least 2 characters. Picking a member replaces any team, and a draft job becomes Assigned when saved.',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          height: 1.4,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ),
                                  )
                                else
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
                                    error: (_, _) => TextButton(
                                      onPressed: () => ref.invalidate(
                                        memberSearchProvider(query),
                                      ),
                                      child: const Text(
                                        'Retry member search',
                                      ),
                                    ),
                                    data: (data) {
                                      final items =
                                          (data['data'] as List? ?? [])
                                              .whereType<Map>();
                                      final lastPage =
                                          (data['last_page'] as num?)
                                              ?.toInt() ??
                                          1;
                                      return Column(
                                        children: [
                                          const SizedBox(height: 8),
                                          if (items.isEmpty)
                                            const Padding(
                                              padding: EdgeInsets.all(16),
                                              child: Text(
                                                'No matching members.',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.black54,
                                                ),
                                              ),
                                            ),
                                          for (final member in items)
                                            _memberRow(member),
                                          if (lastPage > 1)
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                IconButton(
                                                  tooltip: 'Previous members',
                                                  onPressed: !busy && page > 1
                                                      ? () => setState(
                                                          () => page--,
                                                        )
                                                      : null,
                                                  icon: const HugeIcon(
                                                    icon: HugeIcons
                                                        .strokeRoundedArrowLeft01,
                                                    color: Colors.black87,
                                                    size: 22,
                                                  ),
                                                ),
                                                Text(
                                                  'Page $page of $lastPage',
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                  ),
                                                ),
                                                IconButton(
                                                  tooltip: 'Next members',
                                                  onPressed:
                                                      !busy && page < lastPage
                                                      ? () => setState(
                                                          () => page++,
                                                        )
                                                      : null,
                                                  icon: const HugeIcon(
                                                    icon: HugeIcons
                                                        .strokeRoundedArrowRight01,
                                                    color: Colors.black87,
                                                    size: 22,
                                                  ),
                                                ),
                                              ],
                                            ),
                                        ],
                                      );
                                    },
                                  ),
                              ]),
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