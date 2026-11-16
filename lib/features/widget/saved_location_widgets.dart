import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

const Color _cardBorder = Color(0xFFE8ECF0);
const Color _greySoft = Color(0xFFF1F3F5);
const Color _amber = Color(0xFFB26A00);
const Color _amberSoft = Color(0xFFFFF4E0);

/// Square 44px icon button used next to the search field.
class SavedHeaderIconButton extends StatelessWidget {
  const SavedHeaderIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.accent,
    required this.onPressed,
    this.active = false,
    this.loading = false,
  });

  final dynamic icon;
  final String tooltip;
  final Color accent;
  final VoidCallback? onPressed;
  final bool active;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: active ? accent.withValues(alpha: 0.10) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: active ? accent : _cardBorder),
      ),
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        icon: loading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: accent),
              )
            : HugeIcon(icon: icon, color: accent, size: 20),
      ),
    );
  }
}

/// Pill used for the content tabs (All / Points / Area / Route) and group filters.
class SavedPill extends StatelessWidget {
  const SavedPill({
    super.key,
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
    this.count,
  });

  final String label;
  final int? count;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? accent : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? accent : _cardBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : Colors.black54,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.22)
                        : _greySoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : Colors.black54,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Removable tag showing an active filter, sort or group.
class SavedActiveTag extends StatelessWidget {
  const SavedActiveTag({
    super.key,
    required this.label,
    required this.accent,
    required this.onClear,
  });

  final String label;
  final Color accent;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onClear,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: HugeIcon(
                icon: HugeIcons.strokeRoundedCancel01,
                color: accent,
                size: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Soft banner, e.g. "Updating cloud records...".
class SavedInfoBanner extends StatelessWidget {
  const SavedInfoBanner({
    super.key,
    required this.text,
    required this.accent,
    this.loading = true,
  });

  final String text;
  final Color accent;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          if (loading)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: accent),
            ),
          if (loading) const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SavedLoadMoreFooter extends StatelessWidget {
  const SavedLoadMoreFooter({
    super.key,
    required this.isLoading,
    required this.text,
    required this.accent,
  });

  final bool isLoading;
  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isLoading) ...[
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: accent),
            ),
            const SizedBox(width: 10),
          ],
          Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}

class SavedEmptyState extends StatelessWidget {
  const SavedEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
  });

  final dynamic icon;
  final String title;
  final String subtitle;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: HugeIcon(icon: icon, color: accent, size: 34),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SavedSurveyBanner extends StatelessWidget {
  const SavedSurveyBanner({
    super.key,
    required this.accent,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.dismissTooltip,
    required this.onAction,
    required this.onDismiss,
  });

  final Color accent;
  final String title;
  final String body;
  final String actionLabel;
  final String dismissTooltip;
  final VoidCallback onAction;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedMessage01,
                  color: accent,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
              IconButton(
                tooltip: dismissTooltip,
                onPressed: onDismiss,
                visualDensity: VisualDensity.compact,
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedCancel01,
                  color: Colors.black45,
                  size: 18,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8, top: 2),
            child: Text(
              body,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: Colors.black54,
              ),
            ),
          ),
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              actionLabel,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Amber note shown inside a card, e.g. "Waiting for space".
class SavedWarningNote extends StatelessWidget {
  const SavedWarningNote({
    super.key,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _amberSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const HugeIcon(
                icon: HugeIcons.strokeRoundedCloud,
                color: _amber,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _amber,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: Colors.black87,
            ),
          ),
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              actionLabel,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: _amber,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The saved location card.
class SavedLocationTile extends StatelessWidget {
  const SavedLocationTile({
    super.key,
    required this.accent,
    required this.kindIcon,
    required this.kindColor,
    required this.name,
    required this.subtitle,
    required this.dateLabel,
    required this.isCloudSynced,
    required this.selectionMode,
    required this.isSelected,
    required this.compact,
    required this.onTap,
    required this.onLongPress,
    required this.onMore,
    this.groupLabel,
    this.moreTooltip,
    this.cloudTooltip,
    this.warning,
  });

  final Color accent;
  final dynamic kindIcon;
  final Color kindColor;
  final String name;
  final String subtitle;
  final String dateLabel;
  final String? groupLabel;
  final bool isCloudSynced;
  final bool selectionMode;
  final bool isSelected;
  final bool compact;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMore;
  final String? moreTooltip;
  final String? cloudTooltip;
  final Widget? warning;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.all(compact ? 12 : 14),
          decoration: BoxDecoration(
            color: isSelected ? accent.withValues(alpha: 0.06) : null,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? accent : _cardBorder,
              width: isSelected ? 1.6 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (selectionMode) ...[
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected ? accent : Colors.transparent,
                        border: Border.all(
                          color: isSelected ? accent : Colors.black26,
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: isSelected
                          ? const HugeIcon(
                              icon: HugeIcons.strokeRoundedTick02,
                              color: Colors.white,
                              size: 14,
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                  ],
                  Container(
                    width: compact ? 42 : 46,
                    height: compact ? 42 : 46,
                    decoration: BoxDecoration(
                      color: kindColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    alignment: Alignment.center,
                    child: HugeIcon(icon: kindIcon, color: kindColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: compact ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          dateLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black45,
                          ),
                        ),
                        if (groupLabel != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                HugeIcon(
                                  icon: HugeIcons.strokeRoundedFolder01,
                                  color: accent,
                                  size: 12,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    groupLabel!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: accent,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (isCloudSynced)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Tooltip(
                        message: cloudTooltip ?? '',
                        child: HugeIcon(
                          icon: HugeIcons.strokeRoundedCloud,
                          color: accent,
                          size: 18,
                        ),
                      ),
                    ),
                  if (!selectionMode)
                    IconButton(
                      onPressed: onMore,
                      tooltip: moreTooltip,
                      visualDensity: VisualDensity.compact,
                      icon: const HugeIcon(
                        icon: HugeIcons.strokeRoundedMoreVertical,
                        color: Colors.black54,
                        size: 22,
                      ),
                    ),
                ],
              ),
              ?warning,
            ],
          ),
        ),
      ),
    );
  }
}

/// A row inside action sheets (page menu, item actions).
class SavedActionRow extends StatelessWidget {
  const SavedActionRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.accent,
    this.destructive = false,
    this.subtitle,
  });

  final dynamic icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final Color accent;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Theme.of(context).colorScheme.error : accent;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: HugeIcon(icon: icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: destructive ? color : Colors.black87,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom-sheet form with one text field. Pops the trimmed text, or null on cancel.
class SavedTextInputSheet extends StatefulWidget {
  const SavedTextInputSheet({
    super.key,
    required this.accent,
    required this.icon,
    required this.title,
    required this.label,
    required this.initialText,
    required this.confirmLabel,
    required this.cancelLabel,
    this.allowEmpty = false,
  });

  final Color accent;
  final dynamic icon;
  final String title;
  final String label;
  final String initialText;
  final String confirmLabel;
  final String cancelLabel;
  final bool allowEmpty;

  @override
  State<SavedTextInputSheet> createState() => _SavedTextInputSheetState();
}

class _SavedTextInputSheetState extends State<SavedTextInputSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: c, width: w),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
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
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    alignment: Alignment.center,
                    child: HugeIcon(icon: widget.icon, color: accent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, _) {
                  final canSave =
                      widget.allowEmpty || value.text.trim().isNotEmpty;
                  return Column(
                    children: [
                      TextField(
                        controller: _controller,
                        autofocus: true,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: widget.label,
                          filled: true,
                          fillColor: const Color(0xFFF7F7F8),
                          labelStyle: const TextStyle(
                            fontSize: 14,
                            color: Colors.black54,
                          ),
                          floatingLabelStyle: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: accent,
                          ),
                          border: border(_cardBorder),
                          enabledBorder: border(_cardBorder),
                          focusedBorder: border(accent, 1.6),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 16,
                          ),
                        ),
                        onSubmitted: (_) {
                          if (canSave) {
                            Navigator.pop(context, _controller.text.trim());
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: canSave
                              ? () => Navigator.pop(
                                  context,
                                  _controller.text.trim(),
                                )
                              : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            widget.confirmLabel,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    widget.cancelLabel,
                    style: const TextStyle(
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
    );
  }
}

/// Search-first library header with room for the query on narrow screens.
class SavedSearchHeader extends StatelessWidget {
  const SavedSearchHeader({
    super.key,
    required this.controller,
    required this.hintText,
    required this.clearTooltip,
    required this.menuTooltip,
    required this.onChanged,
    required this.onClear,
    required this.onMenu,
  });

  final TextEditingController controller;
  final String hintText;
  final String clearTooltip;
  final String menuTooltip;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: HugeIcon(
                icon: HugeIcons.strokeRoundedSearch01,
                color: Color(0xFF475569),
              ),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => FocusScope.of(context).unfocus(),
                decoration: InputDecoration(
                  hintText: hintText,
                  hintStyle: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF64748B),
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(vertical: 18),
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => value.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      tooltip: clearTooltip,
                      onPressed: onClear,
                      icon: const HugeIcon(
                        icon: HugeIcons.strokeRoundedCancel01,
                        size: 20,
                      ),
                    ),
            ),
            IconButton(
              tooltip: menuTooltip,
              onPressed: onMenu,
              icon: const HugeIcon(icon: HugeIcons.strokeRoundedMoreVertical),
            ),
          ],
        ),
      ),
    );
  }
}
