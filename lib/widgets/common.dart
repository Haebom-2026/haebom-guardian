import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../app/theme.dart';
import '../controllers/guardian_store.dart';
import '../models/approval_request.dart';
import '../models/notification_item.dart';
import '../utils/formatters.dart';

/// 새싹 로고 (해봄)
class SproutMark extends StatelessWidget {
  const SproutMark({super.key, this.size = 36});
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(size / 3)),
      child: Icon(Icons.eco_rounded, size: size * 0.6, color: scheme.primary),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction});
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 0, 8),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ),
          if (actionLabel != null) TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message});
  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: t.colorScheme.outline),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: t.textTheme.titleMedium),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!,
                textAlign: TextAlign.center,
                style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key});
  final ApprovalStatus status;

  @override
  Widget build(BuildContext context) {
    final style = StatusStyle.of(status, Theme.of(context).brightness);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 16, color: style.color),
          const SizedBox(width: 4),
          Text(status.label,
              style: TextStyle(color: style.color, fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
  }
}

/// 가족 호칭 첫 글자 아바타
class FamilyAvatar extends StatelessWidget {
  const FamilyAvatar(this.name, {super.key, this.radius = 22});
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.secondaryContainer,
      foregroundColor: scheme.onSecondaryContainer,
      child: Text(name.isEmpty ? '?' : name.characters.first,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: radius * 0.8)),
    );
  }
}

/// 가족 선택 칩 (전체 + 연결된 가족)
class FamilyFilterBar extends StatelessWidget {
  const FamilyFilterBar({super.key, required this.store});
  final GuardianStore store;

  @override
  Widget build(BuildContext context) {
    if (store.links.length < 2) return const SizedBox.shrink();
    final selected = store.selectedElderId;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _chip(context, '전체 가족', selected == null, () => store.selectElder(null)),
          for (final l in store.links)
            _chip(context, l.displayName, selected == l.elderId, () => store.selectElder(l.elderId)),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap()),
      );
}

/// 알림 아이콘. 사기 의심이면 경고 아이콘.
IconData notificationItemIcon(NotificationItem n) =>
    n.isScam ? Icons.gpp_maybe_rounded : notificationIcon(n.type);

IconData notificationIcon(NotificationType t) => switch (t) {
      NotificationType.sensitiveEntry => Icons.shield_outlined,
      NotificationType.sos => Icons.sos_rounded,
      NotificationType.stuck => Icons.help_outline_rounded,
    };

class NotificationTile extends StatelessWidget {
  const NotificationTile({super.key, required this.item, required this.store, required this.onTap});
  final NotificationItem item;
  final GuardianStore store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final unread = store.isUnread(item);
    final accent = RiskStyle.color(item.risk, t);
    final message = notificationMessage(item, store.nameOf(item.elderId));
    final reason = item.reasonText;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Icon(notificationItemIcon(item), color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(notificationLabel(item),
                              overflow: TextOverflow.ellipsis,
                              style: t.textTheme.labelMedium?.copyWith(color: accent, fontWeight: FontWeight.w700)),
                        ),
                        if (unread) ...[
                          const SizedBox(width: 6),
                          Semantics(
                            label: '확인 전',
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(color: t.colorScheme.error, shape: BoxShape.circle),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(message,
                        style: t.textTheme.bodyLarge?.copyWith(
                            fontWeight: unread ? FontWeight.w700 : FontWeight.w500)),
                    if (reason != null) ...[
                      const SizedBox(height: 2),
                      Text('이유: $reason',
                          style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                    ],
                    const SizedBox(height: 4),
                    Text(formatAgo(item.createdAt, store.now()),
                        style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 1초마다 다시 그려지는 남은 시간 표시
class CountdownBuilder extends StatefulWidget {
  const CountdownBuilder({super.key, required this.builder});
  final WidgetBuilder builder;

  @override
  State<CountdownBuilder> createState() => _CountdownBuilderState();
}

class _CountdownBuilderState extends State<CountdownBuilder> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

class ApprovalCard extends StatelessWidget {
  const ApprovalCard({super.key, required this.request, required this.store, required this.onTap});
  final ApprovalRequest request;
  final GuardianStore store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final who = store.nameOf(request.elderId);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: CountdownBuilder(builder: (context) {
            final now = store.now();
            final status = request.effectiveStatus(now);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    FamilyAvatar(who, radius: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('$who · ${request.appName}',
                          overflow: TextOverflow.ellipsis,
                          style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    StatusBadge(status),
                  ],
                ),
                const SizedBox(height: 10),
                Text(ApprovalActions.label(request.action), style: t.textTheme.bodyLarge),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text(formatDateTime(request.createdAt, now),
                        style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                    if (status == ApprovalStatus.pending)
                      Text('${formatRemaining(request.remaining(now))} 남음',
                          style: t.textTheme.bodySmall?.copyWith(
                              color: StatusStyle.of(status, t.brightness).color, fontWeight: FontWeight.w700)),
                  ],
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

/// 비동기 처리 결과 스낵바
void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// 확인 팝업. 확인 시 true.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            key: const Key('confirm_dialog_cancel'),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const Key('confirm_dialog_ok'),
            style: destructive ? FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError) : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
