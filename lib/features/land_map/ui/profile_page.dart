import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../auth/models/auth_models.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/ui/account_page.dart';
import '../../auth/ui/device_sessions_page.dart';
import '../../../core/localization/app_localizations.dart';
import '../../notifications/ui/notifications_page.dart';
import '../../subscriptions/plans_access_page.dart';
import '../../workspaces/company_create_page.dart';
import '../../workspaces/company_invitations_page.dart';
import '../../workspaces/company_members_page.dart';
import '../../workspaces/field_jobs_page.dart';
import '../../workspaces/organization_page.dart';
import '../../workspaces/workspace_provider.dart';
import '../../widget/profile_widget.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  // One accent per workspace. Everything on this page uses it.
  static const Color _personalAccent = Color(0xFF001F3F);
  static const Color _companyAccent = Color(0xFF197568);
  static const Color _pageBackground = Color(0xFFF3F3F4);

  Color _accentFor(bool isCompany) =>
      isCompany ? _companyAccent : _personalAccent;

  void _push(Widget page) {
    Navigator.of(context)
        .push<void>(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authSessionProvider);
    final workspace = ref.watch(workspaceProvider);
    final l10n = context.l10n;
    final baseTheme = Theme.of(context);
    final verified = session.isLoggedIn && session.isVerified;
    final isCompany = workspace.activeCompanyId != null;
    final accent = _accentFor(isCompany);

    // Wrapping the page in this Theme makes every child use one accent color.
    return Theme(
      data: baseTheme.copyWith(
        colorScheme: baseTheme.colorScheme.copyWith(primary: accent),
      ),
      child: ColoredBox(
        color: _pageBackground,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            _ProfileHeader(
              session: session,
              workspaceLabel: verified ? workspace.label : null,
              isCompany: isCompany,
              onAvatarTap: () => _push(const AccountPage()),
              onWorkspaceTap: _showWorkspaceSelector,
            ),

            // ── Account ────────────────────────────────────────
            ProfileSection(
              title: l10n.t('Account'),
              children: [
                ProfileTile(
                  icon: HugeIcons.strokeRoundedUser,
                  title: l10n.t('Account'),
                  subtitle: session.isLoggedIn
                      ? 'Manage your profile and sign-in details'
                      : l10n.t(
                          'Sign in only when you want to sync data to the server.',
                        ),
                  onTap: () => _push(const AccountPage()),
                ),
                if (session.isLoggedIn)
                  ProfileTile(
                    icon: HugeIcons.strokeRoundedSmartPhone01,
                    title: 'Signed-in devices',
                    subtitle: 'Review sessions and sign out other devices',
                    onTap: () => _push(const DeviceSessionsPage()),
                  ),
                if (verified)
                  ProfileTile(
                    icon: HugeIcons.strokeRoundedNotification01,
                    title: 'Notifications',
                    subtitle: 'View announcements and manage mobile alerts',
                    onTap: () => _push(const NotificationsPage()),
                  ),
                if (verified)
                  ProfileTile(
                    icon: HugeIcons.strokeRoundedCrown,
                    title: 'Plans & Access',
                    subtitle: 'Current plan, usage and approval status',
                    onTap: () => _push(const PlansAccessPage()),
                  ),
              ],
            ),

            // ── Companies ──────────────────────────────────────
            if (verified)
              ProfileSection(
                title: l10n.t('Companies'),
                children: [
                  ProfileTile(
                    icon: HugeIcons.strokeRoundedMail01,
                    title: 'Company invitations',
                    subtitle: 'Review invitations to join a company',
                    onTap: () => _push(const CompanyInvitationsPage()),
                  ),
                  ProfileTile(
                    icon: HugeIcons.strokeRoundedAddCircle,
                    title: 'Create company',
                    subtitle: 'Create a company workspace you own',
                    onTap: _createCompany,
                  ),
                ],
              ),

            // ── Active company ─────────────────────────────────
            if (verified && isCompany)
              ProfileSection(
                title: workspace.activeCompany?.name ?? 'Company',
                children: [
                  if (canViewCompanyDirectory(workspace, session.user?.role))
                    ProfileTile(
                      icon: HugeIcons.strokeRoundedUserGroup,
                      title: 'Company members',
                      subtitle: 'Members and pending invitations',
                      onTap: () => _push(const CompanyMembersPage()),
                    ),
                  ProfileTile(
                    icon: HugeIcons.strokeRoundedFolder01,
                    title: 'Projects & Teams',
                    subtitle: 'Company projects and team members',
                    onTap: () => _push(const OrganizationPage()),
                  ),
                  ProfileTile(
                    icon: HugeIcons.strokeRoundedTask01,
                    title: 'Field jobs',
                    subtitle: 'Company assignments and progress',
                    onTap: () => _push(const FieldJobsPage()),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _createCompany() async {
    final token = ref.read(authSessionProvider).token;
    final company = await Navigator.of(context).push<CompanyWorkspace>(
      MaterialPageRoute(builder: (_) => const CompanyCreatePage()),
    );
    if (!mounted ||
        company == null ||
        token != ref.read(authSessionProvider).token) {
      return;
    }
    final error = ref.read(workspaceProvider).error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error == null
              ? 'Company created. Select it from Workspace when ready.'
              : 'Company created. Refresh your workspace list to see it.',
        ),
      ),
    );
  }

  Widget _workspaceOption({
    required BuildContext context,
    required bool selected,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    // Same accent as the page, not the app theme primary.
    final accent =
        _accentFor(ref.read(workspaceProvider).activeCompanyId != null);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.1)
              : const Color(0xFFF1F4F7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          title == context.l10n.t('Personal workspace')
              ? Icons.person_outline_rounded
              : Icons.business_outlined,
          color: selected ? accent : const Color(0xFF526579),
        ),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: Colors.black54),
      ),
      trailing:
          selected ? Icon(Icons.check_circle_rounded, color: accent) : null,
      onTap: onTap,
    );
  }

  Future<void> _showWorkspaceSelector() async {
    ref.read(workspaceProvider.notifier).refresh();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final workspace = ref.watch(workspaceProvider);
          final theme = Theme.of(context);
          return SafeArea(
            top: false,
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.72,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD5DCE5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.l10n.t('Choose workspace'),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: context.l10n.t('Refresh'),
                          onPressed: workspace.isLoading
                              ? null
                              : () => ref
                                    .read(workspaceProvider.notifier)
                                    .refresh(),
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
                    child: Text(
                      context.l10n.t(
                        'Personal records and each company workspace stay separate.',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.black54,
                        height: 1.4,
                      ),
                    ),
                  ),
                  if (workspace.isLoading)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  if (workspace.error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.cloud_off_outlined, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Unable to refresh workspaces. Your current selection is unchanged.',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (!workspace.isLoading)
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          _workspaceOption(
                            context: context,
                            selected: workspace.activeCompanyId == null,
                            title: context.l10n.t('Personal workspace'),
                            subtitle: context.l10n.t('Your individual records'),
                            onTap: () async {
                              await ref
                                  .read(workspaceProvider.notifier)
                                  .selectCompany(null);
                              if (sheetContext.mounted) {
                                Navigator.of(sheetContext).pop();
                              }
                            },
                          ),
                          ...workspace.companies.map(
                            (company) => _workspaceOption(
                              context: context,
                              selected: workspace.activeCompanyId == company.id,
                              title: company.name,
                              subtitle: companyRoleLabel(company.role),
                              onTap: () async {
                                await ref
                                    .read(workspaceProvider.notifier)
                                    .selectCompany(company.id);
                                if (sheetContext.mounted) {
                                  Navigator.of(sheetContext).pop();
                                }
                              },
                            ),
                          ),
                          if (workspace.companies.isEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                              child: Text(
                                context.l10n.t(
                                  'No company workspace is available for this account.',
                                ),
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Centered avatar, name below it, email, and a workspace chip.
class _ProfileHeader extends StatelessWidget {
  final AuthSession session;
  final String? workspaceLabel;
  final bool isCompany;
  final VoidCallback onAvatarTap;
  final VoidCallback onWorkspaceTap;

  const _ProfileHeader({
    required this.session,
    required this.workspaceLabel,
    required this.isCompany,
    required this.onAvatarTap,
    required this.onWorkspaceTap,
  });

  String _initials(String name, String email) {
    final source = name.trim().isNotEmpty ? name.trim() : email.trim();
    if (source.isEmpty) return '?';
    final parts = source.split(RegExp(r'\s+'));
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    return source[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final user = session.user;
    final name = user?.name.trim() ?? '';
    final email = user?.email.trim() ?? '';
    final signedIn = session.isLoggedIn;

    return Container(
      color: Colors.white,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 22),
      child: Column(
        children: [
          GestureDetector(
            onTap: onAvatarTap,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 46,
                  backgroundColor: accent.withValues(alpha: 0.12),
                  child: signedIn
                      ? Text(
                          _initials(name, email),
                          style: TextStyle(
                            color: accent,
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : HugeIcon(
                          icon: HugeIcons.strokeRoundedUser,
                          color: accent,
                          size: 38,
                        ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.edit_rounded,
                      size: 13,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            signedIn ? (name.isNotEmpty ? name : email) : 'Not signed in',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            signedIn
                ? (name.isNotEmpty ? email : 'Signed in')
                : 'Tap the picture to sign in and sync your data',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
          if (workspaceLabel != null) ...[
            const SizedBox(height: 14),
            InkWell(
              onTap: onWorkspaceTap,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isCompany
                          ? Icons.business_outlined
                          : Icons.person_outline_rounded,
                      size: 15,
                      color: accent,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        workspaceLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: accent,
                        ),
                      ),
                    ),
                    Icon(Icons.keyboard_arrow_down_rounded,
                        size: 18, color: accent),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
