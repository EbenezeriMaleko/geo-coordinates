import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/providers/auth_provider.dart';
import 'workspace_provider.dart';
import 'organization_page.dart';
import 'field_jobs_page.dart';
import 'company_members_page.dart';

class WorkspaceIdentityBar extends ConsumerWidget {
  const WorkspaceIdentityBar({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionProvider);
    if (!session.isLoggedIn || !session.isVerified) {
      return const SizedBox.shrink();
    }
    final workspace = ref.watch(workspaceProvider);
    final company = workspace.activeCompanyId != null;
    final accent = company ? const Color(0xFF197568) : const Color(0xFF001F3F);
    return Material(
      color: company ? const Color(0xFFF0F8F5) : const Color(0xFFF5F7FA),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: accent.withValues(alpha: .18)),
            left: BorderSide(color: accent, width: 3),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        child: Row(
          children: [
            Expanded(
              child: PopupMenuButton<int>(
                enabled: !workspace.isLoading,
                tooltip: 'Switch workspace',
                onSelected: (id) async {
                  try {
                    await ref
                        .read(workspaceProvider.notifier)
                        .selectCompany(id == 0 ? null : id);
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Unable to switch workspace. Please retry.',
                          ),
                        ),
                      );
                    }
                  }
                },
                itemBuilder: (_) => [
                  CheckedPopupMenuItem(
                    value: 0,
                    checked: !company,
                    child: const Text('Personal workspace'),
                  ),
                  for (final item in workspace.companies)
                    CheckedPopupMenuItem(
                      value: item.id,
                      checked: workspace.activeCompanyId == item.id,
                      child: Text(item.name),
                    ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        company
                            ? Icons.business_outlined
                            : Icons.person_outline_rounded,
                        color: accent,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              company
                                  ? workspace.activeCompany?.name ??
                                        'Company workspace'
                                  : 'My workspace',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: accent,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            Text(
                              company
                                  ? 'Company · ${companyRoleLabel(workspace.activeCompany?.role)}'
                                  : 'Personal workspace',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: const Color(0xFF667085)),
                            ),
                          ],
                        ),
                      ),
                      if (workspace.isLoading)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        const Icon(Icons.expand_more_rounded, size: 20),
                    ],
                  ),
                ),
              ),
            ),
            if (company)
              PopupMenuButton<String>(
                tooltip: 'Company tools',
                enabled: !workspace.isLoading,
                icon: Icon(Icons.apps_rounded, color: accent, size: 22),
                onSelected: (value) => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => value == 'members'
                        ? const CompanyMembersPage()
                        : value == 'teams'
                        ? const OrganizationPage()
                        : const FieldJobsPage(),
                  ),
                ),
                itemBuilder: (_) => [
                  if (canViewCompanyDirectory(workspace, session.user?.role))
                    const PopupMenuItem(
                      value: 'members',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.people_outline, size: 20),
                        title: Text('Company members'),
                      ),
                    ),
                  PopupMenuItem(
                    value: 'teams',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.groups_outlined, size: 20),
                      title: Text('Projects & Teams'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'jobs',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.assignment_outlined, size: 20),
                      title: Text('Field jobs'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
