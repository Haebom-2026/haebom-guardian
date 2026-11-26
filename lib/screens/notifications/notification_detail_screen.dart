import 'package:material_ui/material_ui.dart';

import '../../app/dependencies.dart';
import '../../app/theme.dart';
import '../../models/notification_item.dart';
import '../../models/sensitivity.dart';
import '../../repositories/guardian_repository.dart';
import '../../utils/formatters.dart';
import '../../widgets/common.dart';

/// 알림 상세.
///
/// 화면을 여는 것만으로는 확인 처리하지 않는다. 보호자가 "확인했어요" 버튼을 눌러야
/// `readBy.{guardianUid}`가 기록된다 (INTEGRATION_REVIEW #9, 고령자 앱은 2차에 이 값을 구독해
/// "○○가 확인했어요"를 표시할 수 있다).
/// 알림 탭(로컬 알림/FCM)으로 진입했는데 문서가 없거나 권한이 없으면 안내 화면을 보여준다.
class NotificationDetailScreen extends StatefulWidget {
  const NotificationDetailScreen({super.key, required this.notificationId});
  final String notificationId;

  @override
  State<NotificationDetailScreen> createState() => _NotificationDetailScreenState();
}

class _NotificationDetailScreenState extends State<NotificationDetailScreen> {
  late Future<NotificationItem> _future;
  bool _started = false;
  bool _confirming = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final repo = AppScope.of(context).repository;
    _future = repo.getNotification(widget.notificationId);
  }

  Future<void> _confirm(String id) async {
    setState(() => _confirming = true);
    try {
      await AppScope.of(context).repository.markNotificationRead(id);
    } on RepositoryException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.userMessage)));
      }
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).store;
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('알림 상세')),
      body: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) => FutureBuilder<NotificationItem>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                final e = snap.error;
                return ListView(
                  children: [
                    EmptyState(
                      icon: Icons.search_off_rounded,
                      title: '알림을 열 수 없습니다',
                      message: e is RepositoryException ? e.userMessage : '잠시 후 다시 시도해 주세요.',
                    ),
                  ],
                );
              }
              // 확인 상태가 바로 반영되도록 실시간 목록의 최신 문서를 우선 사용한다.
              final n = store.notifications.where((x) => x.id == snap.data!.id).firstOrNull ?? snap.data!;
              final who = store.nameOf(n.elderId);
              final confirmedAt = n.readBy[store.guardianId];
              final accent = RiskStyle.color(n.risk, t);
              return ListView(
                padding: const EdgeInsets.all(Space.page),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(notificationItemIcon(n), color: accent),
                              const SizedBox(width: 8),
                              Text(
                                notificationLabel(n),
                                style: t.textTheme.labelLarge?.copyWith(color: accent, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            notificationMessage(n, who),
                            style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 16),
                          _row(context, '가족', '$who (${store.linkFor(n.elderId)?.elderName ?? '-'})'),
                          if (n.appName.isNotEmpty) _row(context, '서비스', n.appName),
                          if (n.category != null && n.category != SensitivityCategory.none)
                            _row(context, '분류', n.category!.label),
                          if (n.reasonText != null) _row(context, '이유', n.reasonText!),
                          _row(context, '발생 시간', formatDateTime(n.createdAt, store.now())),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (confirmedAt == null)
                    FilledButton.icon(
                      key: const Key('notification_confirm'),
                      onPressed: _confirming ? null : () => _confirm(n.id),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('확인했어요'),
                    )
                  else
                    Row(
                      key: const Key('notification_confirmed'),
                      children: [
                        Icon(Icons.check_circle_rounded, color: t.colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '확인함 · ${formatDateTime(confirmedAt, store.now())}',
                            style: t.textTheme.bodyLarge,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 16),
                  _Guide(type: n.type, scam: n.isScam),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: Text(value, style: t.textTheme.bodyLarge)),
        ],
      ),
    );
  }
}

class _Guide extends StatelessWidget {
  const _Guide({required this.type, this.scam = false});
  final NotificationType type;
  final bool scam;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final text = scam
        ? '해봄 도우미가 기관·가족 사칭 같은 사기 의심 상황으로 판단해 안내를 멈췄습니다. '
            '가족에게 바로 전화해 누가 무엇을 하라고 했는지 확인해 주세요. '
            '검찰·경찰·은행은 전화로 돈을 옮기라고 하지 않습니다.'
        : switch (type) {
      NotificationType.sensitiveEntry =>
        '가족이 이 서비스를 이용한다는 사실을 알려드리기로 동의해 보낸 알림입니다. '
            '입력한 개인정보, 비밀번호, 계좌 정보나 거래 내용은 해봄이 수집하거나 확인하지 않습니다.\n\n'
            '걱정되는 점이 있다면 직접 전화로 안부를 확인해 보세요.',
      NotificationType.sos =>
        '가족이 SOS 버튼으로 도움을 요청했습니다. 바로 전화로 상황을 확인해 주세요. '
            '긴급한 상황이라면 112 또는 119에 도움을 요청하세요.',
      NotificationType.stuck =>
        '해봄 도우미가 가족이 앱 사용에 어려움을 겪는 것 같다고 판단했습니다. '
            '시간이 될 때 연락해 함께 방법을 알아봐 주세요.',
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: t.colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: t.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: t.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
