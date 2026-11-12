import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../auth/providers/auth_provider.dart';
import '../subscriptions/entitlement_provider.dart';
import 'workspace_provider.dart';
import 'workspace_page_style.dart';
import 'job_review_history.dart';

final jobReviewProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, int>((ref, job) async {
      ref.watch(workspaceProvider);
      final session = ref.watch(authSessionProvider);
      final response = await ApiClient.getJson(
        '/field-jobs/$job/review',
        bearerToken: session.token,
      );
      if (response.statusCode == 503) {
        throw Exception('Job reviews are not available on this server yet.');
      }
      if (response.statusCode != 200) {
        throw Exception('Unable to load the job review.');
      }
      final body = jsonDecode(response.body);
      return {
        ...(body['data'] is Map
            ? Map<String, dynamic>.from(body['data'] as Map)
            : <String, dynamic>{}),
        'permissions': body['permissions'] is Map
            ? body['permissions']
            : <String, dynamic>{},
      };
    });

class JobReviewPage extends ConsumerStatefulWidget {
  const JobReviewPage({
    super.key,
    required this.job,
    required this.company,
    required this.manager,
    required this.writable,
    required this.canSubmit,
    required this.onChanged,
  });
  final Map job;
  final int company;
  final bool manager;
  final bool writable;
  final bool canSubmit;
  final VoidCallback onChanged;
  @override
  ConsumerState<JobReviewPage> createState() => _JobReviewPageState();
}

class _JobReviewPageState extends ConsumerState<JobReviewPage> {
  final note = TextEditingController();
  bool busy = false;
  String? error;
  bool reopened = false;
  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> act(String action) async {
    if (action == 'changes_requested' && note.text.trim().isEmpty) {
      setState(() => error = 'Add a note explaining the requested changes.');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          action == 'approved'
              ? 'Approve job?'
              : action == 'reopen'
              ? 'Reopen for corrections?'
              : action == 'submit'
              ? 'Submit for review?'
              : 'Request changes?',
        ),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirm'),
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
    if (confirm != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final session = ref.read(authSessionProvider);
      if (widget.company != ref.read(workspaceProvider).activeCompanyId ||
          !session.isVerified) {
        throw Exception('Workspace changed. Reopen the review.');
      }
      final response = await ApiClient.postJson(
        '/field-jobs/${widget.job['id']}/review',
        bearerToken: session.token,
        body: {
          'action': action,
          'note': note.text.trim().isEmpty ? null : note.text.trim(),
        },
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = jsonDecode(response.body);
        throw Exception(
          body is Map
              ? body['message'] ?? 'Unable to update review.'
              : 'Unable to update review.',
        );
      }
      if (!mounted) return;
      if (action == 'reopen') reopened = true;
      note.clear();
      widget.onChanged();
      ref.invalidate(jobReviewProvider((widget.job['id'] as num).toInt()));
      ref.invalidate(reviewHistoryProvider);
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = (widget.job['id'] as num).toInt();
    final review = ref.watch(jobReviewProvider(id));
    final access = ref.watch(entitlementProvider);
    final allowed =
        widget.writable &&
        access.asData?.value['company.review_workflow']?.allowed == true &&
        widget.company == ref.watch(workspaceProvider).activeCompanyId;
    final actor = ref.watch(authSessionProvider).user?.id;
    return PopScope(
      canPop: !busy,
      child: WorkspaceScaffold(
        company: true,
        appBar: AppBar(
          title: const Text('Job review'),
          actions: [
            IconButton(
              tooltip: 'Refresh review',
              onPressed: busy
                  ? null
                  : () {
                      ref.invalidate(jobReviewProvider(id));
                      ref.invalidate(reviewHistoryProvider);
                      ref.invalidate(entitlementProvider);
                      ref.invalidate(workspaceAccessSnapshotProvider);
                    },
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: review.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (failure, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      failure.toString().replaceFirst('Exception: ', ''),
                      textAlign: TextAlign.center,
                    ),
                    TextButton(
                      onPressed: () => ref.invalidate(jobReviewProvider(id)),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
            data: (data) {
              final state = data?['state']?.toString();
              final self =
                  data?['submitted_by']?.toString() == actor?.toString();
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    widget.job['title']?.toString() ?? 'Field job',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(state?.replaceAll('_', ' ') ?? 'Not submitted'),
                  const Divider(height: 32),
                  if (data?['review_note'] != null)
                    Text(data!['review_note'].toString()),
                  if (access.hasError)
                    const Text(
                      'Feature access could not be verified. Refresh to retry.',
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
                  if (allowed &&
                      data?['permissions'] is Map &&
                      data!['permissions']['can_submit'] == true &&
                      !reopened &&
                      widget.job['status'] == 'completed' &&
                      (state == null || state == 'correcting'))
                    FilledButton(
                      onPressed: busy ? null : () => act('submit'),
                      child: const Text('Submit for review'),
                    ),
                  if (allowed &&
                      data?['permissions'] is Map &&
                      data!['permissions']['can_reopen'] == true &&
                      state == 'changes_requested')
                    FilledButton(
                      onPressed: busy ? null : () => act('reopen'),
                      child: const Text('Reopen for corrections'),
                    ),
                  if (state == 'correcting')
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Corrections in progress. Complete the job before resubmitting.',
                      ),
                    ),
                  if (self && state == 'submitted')
                    const Text(
                      'Another company manager must review this submission.',
                    ),
                  if (allowed &&
                      data?['permissions'] is Map &&
                      data!['permissions']['can_decide'] == true &&
                      state == 'submitted' &&
                      !self &&
                      data['submitted_by'] != null) ...[
                    TextField(
                      controller: note,
                      enabled: !busy,
                      maxLength: 5000,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: 'Review note',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: busy ? null : () => act('approved'),
                      child: const Text('Approve'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: busy ? null : () => act('changes_requested'),
                      child: const Text('Request changes'),
                    ),
                  ],
                  const SizedBox(height: 20),
                  JobReviewHistory(company: widget.company, job: id),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
