import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../auth/providers/auth_provider.dart';
import 'workspace_provider.dart';

List<String> permittedJobActions({
  required String status,
  required bool writable,
  required bool manager,
  required int? membership,
  required int? assignee,
  bool? canStart,
  bool? canComplete,
  bool teamAssigned = false,
}) {
  if (!writable) {
    return const [];
  }
  final legacyAllowed =
      manager ||
      (!teamAssigned && membership != null && membership == assignee);
  return [
    if (status == 'assigned' && (canStart ?? legacyAllowed)) 'in_progress',
    if (status == 'in_progress' && (canComplete ?? legacyAllowed)) 'completed',
    if (manager && ['draft', 'assigned', 'in_progress'].contains(status))
      'cancelled',
  ];
}

class JobProgressActions extends ConsumerStatefulWidget {
  const JobProgressActions({
    super.key,
    required this.job,
    required this.workspaceId,
    required this.writable,
    required this.manager,
    required this.membership,
    required this.onChanged,
  });
  final Map job;
  final int? workspaceId;
  final bool writable;
  final bool manager;
  final int? membership;
  final VoidCallback onChanged;
  @override
  ConsumerState<JobProgressActions> createState() => _JobProgressActionsState();
}

class _JobProgressActionsState extends ConsumerState<JobProgressActions> {
  bool busy = false;
  String? error;
  Future<void> change(String status) async {
    final token = ref.read(authSessionProvider).token;
    if (status == 'cancelled') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cancel field job?'),
          content: const Text(
            'This closes the job. Existing company records remain unchanged.',
          ),
          actions: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Cancel job'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Keep job'),
                ),
              ],
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (widget.workspaceId != ref.read(workspaceProvider).activeCompanyId ||
          token != ref.read(authSessionProvider).token) {
        throw Exception(
          'Workspace or session changed. Reopen the job and try again.',
        );
      }
      final response = await ApiClient.patchJson(
        '/field-jobs/${widget.job['id']}',
        body: {'status': status},
        bearerToken: token,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = jsonDecode(response.body);
        throw Exception(
          body is Map
              ? body['message'] ?? 'Unable to update job.'
              : 'Unable to update job.',
        );
      }
      if (!mounted) return;
      widget.onChanged();
      Navigator.of(context).pop();
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = failure.toString().replaceFirst('Exception: ', '');
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = permittedJobActions(
      status: widget.job['status']?.toString() ?? '',
      writable: widget.writable,
      manager: widget.manager,
      membership: widget.membership,
      assignee: (widget.job['assignee_membership_id'] as num?)?.toInt(),
      canStart: widget.job['can_start'] is bool
          ? widget.job['can_start'] as bool
          : null,
      canComplete: widget.job['can_complete'] is bool
          ? widget.job['can_complete'] as bool
          : null,
      teamAssigned: widget.job['company_team_id'] != null,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        for (final action in actions)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: action == 'cancelled'
                ? OutlinedButton(
                    onPressed: busy ? null : () => change(action),
                    child: const Text('Cancel job'),
                  )
                : FilledButton.icon(
                    onPressed: busy ? null : () => change(action),
                    icon: Icon(
                      action == 'completed'
                          ? Icons.check
                          : Icons.play_arrow_outlined,
                      size: 18,
                    ),
                    label: Text(
                      busy
                          ? 'Updating...'
                          : action == 'completed'
                          ? 'Complete job'
                          : 'Start job',
                    ),
                  ),
          ),
      ],
    );
  }
}
