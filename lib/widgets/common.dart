import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../app/theme.dart';
import '../controllers/guardian_store.dart';
import '../models/approval_request.dart';
import '../models/notification_item.dart';
import '../models/sensitivity.dart';
import '../utils/formatters.dart';

/// 해봄 로고: 짙은 녹색 바탕 + 노란 햇살 (앱 아이콘과 같은 모양)
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 36});
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: HaebomTokens.light.primary, borderRadius: BorderRadius.circular(size * 0.3)),
        child: Icon(Icons.wb_sunny_rounded, size: size * 0.62, color: HaebomTokens.light.brand),
      ),
    );
  }
}

/// 섹션 제목 (20, 굵게). [count]가 있으면 제목 옆에 숫자, [actionLabel]이 있으면 오른쪽 이동 버튼.
class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.title, {
    super.key,
    this.count,
    this.countKey,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(Space.page, Space.section, Space.page - 8, 8),
  });
  final String title;
  final int? count;
  final Key? countKey;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final k = HaebomTokens.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 6,
                children: [
                  Text(title, style: t.textTheme.titleLarge),
                  if (count != null) Text('$count', key: countKey, style: t.textTheme.titleLarge?.copyWith(color: k.primary)),
                ],
              ),
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
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: Space.page),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: t.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: t.textTheme.titleSmall),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, textAlign: TextAlign.center, style: t.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// 승인 상태: 아이콘 + 글자 (색만으로 구분하지 않음)
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key});
  final ApprovalStatus status;

  @override
  Widget build(BuildContext context) {
    final style = StatusStyle.of(status, Theme.of(context).brightness);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(style.icon, size: 18, color: style.color),
        const SizedBox(width: 4),
        Text(
          status.label,
          style: TextStyle(color: style.color, fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ],
    );
  }
}

/// 아바타 글자: 실명이 세 글자 이상이면 이름(뒤 두 글자, 예: 김순자 → 순자), 아니면 실명, 실명이 없으면 호칭 첫 글자.
/// 호칭 첫 글자("어", "아")는 뜻이 없어 쓰지 않는다.
String avatarText(String elderName, {String fallback = ''}) {
  final name = elderName.trim().characters;
  if (name.length >= 3) return name.skip(name.length - 2).toString();
  if (name.isNotEmpty) return name.toString();
  final f = fallback.trim().characters;
  return f.isEmpty ? '?' : f.first;
}

/// 가족 아바타 (연한 노랑 바탕 + 이름 1~2글자)
class FamilyAvatar extends StatelessWidget {
  const FamilyAvatar(this.text, {super.key, this.radius = 22});
  final String text;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: CircleAvatar(
        radius: radius,
        backgroundColor: scheme.secondaryContainer,
        foregroundColor: scheme.onSecondaryContainer,
        child: Padding(
          padding: EdgeInsets.all(radius * 0.22),
          child: FittedBox(
            child: Text(
              text,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: radius * 0.7),
            ),
          ),
        ),
      ),
    );
  }
}

/// 가족 선택 칩 (전체 + 연결된 가족). 연결된 가족이 1명이면 가족 칩은 숨긴다.
/// [leading]: 같은 줄 앞에 둘 다른 필터 칩 (예: 알림 화면의 전체 / 확인 전)
class FamilyFilterBar extends StatelessWidget {
  const FamilyFilterBar({
    super.key,
    required this.store,
    this.leading = const [],
    this.padding = const EdgeInsets.symmetric(horizontal: Space.page),
  });
  final GuardianStore store;
  final List<Widget> leading;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final showFamily = store.links.length >= 2;
    if (!showFamily && leading.isEmpty) return const SizedBox.shrink();
    final selected = store.selectedElderId;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          for (final w in leading) Padding(padding: const EdgeInsets.only(right: 8), child: w),
          if (showFamily && leading.isNotEmpty)
            Container(
              width: 1,
              height: 24,
              margin: const EdgeInsets.only(right: 8),
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          if (showFamily) ...[
            _chip(context, '전체 가족', selected == null, () => store.selectElder(null)),
            for (final l in store.links)
              _chip(context, l.displayName, selected == l.elderId, () => store.selectElder(l.elderId)),
          ],
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label, bool selected, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: FilterPill(label: label, selected: selected, onSelected: onTap),
  );
}

/// 필터 칩. 선택되면 연한 녹색 바탕 + 녹색 굵은 글자 (색 + 굵기로 구분)
class FilterPill extends StatelessWidget {
  const FilterPill({super.key, required this.label, required this.selected, required this.onSelected});
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final k = HaebomTokens.of(context);
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      labelStyle: TextStyle(
        fontSize: 15,
        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        color: selected ? k.primary : k.text,
      ),
      onSelected: (_) => onSelected(),
    );
  }
}

/// 알림 아이콘. 사기 의심이면 경고 아이콘.
IconData notificationItemIcon(NotificationItem n) => n.isScam ? Icons.gpp_maybe_rounded : notificationIcon(n.type);

IconData notificationIcon(NotificationType t) => switch (t) {
  NotificationType.sensitiveEntry => Icons.shield_outlined,
  NotificationType.sos => Icons.sos_rounded,
  NotificationType.stuck => Icons.support_rounded,
};

/// 위험도 글자 (색만으로 구분하지 않도록)
String riskLabel(RiskTone tone) => switch (tone) {
  RiskTone.normal => '일반',
  RiskTone.caution => '주의',
  RiskTone.danger => '긴급',
};

/// 목록 줄 사이 구분선 (아이콘 열 다음부터)
class RowDivider extends StatelessWidget {
  const RowDivider({super.key});

  @override
  Widget build(BuildContext context) => const Divider(indent: Space.page + 36, endIndent: Space.page);
}

/// 모든 목록이 쓰는 한 줄 구성: [아이콘 24] [제목 / 보조 정보] [오른쪽 상태]
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.leading,
    required this.title,
    this.lines = const [],
    this.trailing,
    this.onTap,
  });
  final Widget leading;
  final Widget title;
  final List<Widget> lines;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.page, 14, Space.page, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: SizedBox(width: 24, child: leading),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    for (final l in lines) ...[const SizedBox(height: 3), l],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// 알림 한 줄. 확인 전이면 제목 굵게 + 녹색 점 (낭독: "확인 전").
class NotificationTile extends StatelessWidget {
  const NotificationTile({super.key, required this.item, required this.store, required this.onTap});
  final NotificationItem item;
  final GuardianStore store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final k = HaebomTokens.of(context);
    final unread = store.isUnread(item);
    final accent = RiskStyle.color(item.risk, t);
    final reason = item.reasonText;
    return ListRow(
      onTap: onTap,
      leading: Icon(notificationItemIcon(item), color: accent, size: 24),
      title: Text(
        notificationMessage(item, store.nameOf(item.elderId)),
        style: t.textTheme.bodyLarge?.copyWith(fontWeight: unread ? FontWeight.w800 : FontWeight.w500),
      ),
      lines: [
        Text(
          '${notificationLabel(item)} · ${formatAgo(item.createdAt, store.now())}',
          style: t.textTheme.bodySmall?.copyWith(
            color: item.risk == RiskTone.normal ? k.textSub : accent,
            fontWeight: item.risk == RiskTone.normal ? null : FontWeight.w700,
          ),
        ),
        if (reason != null) Text('이유: $reason', style: t.textTheme.bodySmall),
      ],
      trailing: unread
          ? Semantics(
              label: '확인 전',
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: k.primary, shape: BoxShape.circle),
                ),
              ),
            )
          : null,
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

/// 승인 요청 한 줄: [상태 아이콘] 누구 · 서비스 / 요청 내용 / 시각 [상태 글자]
class ApprovalCard extends StatelessWidget {
  const ApprovalCard({super.key, required this.request, required this.store, required this.onTap});
  final ApprovalRequest request;
  final GuardianStore store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final who = store.nameOf(request.elderId);
    return CountdownBuilder(
      builder: (context) {
        final now = store.now();
        final status = request.effectiveStatus(now);
        final style = StatusStyle.of(status, t.brightness);
        return ListRow(
          onTap: onTap,
          leading: Icon(style.icon, color: style.color, size: 24),
          title: Text('$who · ${request.appName}', style: t.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
          lines: [
            Text(ApprovalActions.label(request.action), style: t.textTheme.bodyMedium),
            Text(
              status == ApprovalStatus.pending
                  ? '${formatDateTime(request.createdAt, now)} · ${formatRemaining(request.remaining(now))} 남음'
                  : formatDateTime(request.createdAt, now),
              style: t.textTheme.bodySmall,
            ),
          ],
          trailing: Padding(padding: const EdgeInsets.only(top: 2), child: StatusBadge(status)),
        );
      },
    );
  }
}

/// "도움이 필요한 일" 상자: 주의(주황)·긴급(빨강) 바탕 + 아이콘 + 종류 글자 + 확인 버튼.
/// 홈과 승인 탭에서 같은 모양으로 쓴다. 버튼은 상세 화면으로만 이동한다 (바로 승인·거절하지 않음).
class HelpCard extends StatelessWidget {
  const HelpCard({
    super.key,
    required this.tone,
    required this.icon,
    required this.tag,
    required this.title,
    this.lines = const [],
    required this.buttonLabel,
    this.buttonKey,
    required this.onPressed,
  });
  final RiskTone tone;
  final IconData icon;

  /// 종류: SOS / 사기 의심 / 도움 필요 / 승인 대기
  final String tag;
  final String title;
  final List<Widget> lines;
  final String buttonLabel;
  final Key? buttonKey;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final color = RiskStyle.color(tone, t);
    return Material(
      color: RiskStyle.background(tone, t),
      borderRadius: BorderRadius.circular(Space.radius),
      clipBehavior: Clip.antiAlias,
      // 상자 어디를 눌러도 버튼과 같은 상세 화면으로 이동
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(Space.card),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: color, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tag,
                          style: t.textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(title, style: t.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800)),
                        for (final l in lines) ...[const SizedBox(height: 2), l],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton(key: buttonKey, onPressed: onPressed, child: Text(buttonLabel)),
            ],
          ),
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
        title: Text(title, style: Theme.of(ctx).textTheme.titleLarge),
        content: Text(message, style: Theme.of(ctx).textTheme.bodyLarge),
        actions: [
          TextButton(
            key: const Key('confirm_dialog_cancel'),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const Key('confirm_dialog_ok'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(64, 48),
              backgroundColor: destructive ? scheme.error : null,
              foregroundColor: destructive
                  ? (scheme.brightness == Brightness.dark ? const Color(0xFF2A0F0C) : Colors.white)
                  : null,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
