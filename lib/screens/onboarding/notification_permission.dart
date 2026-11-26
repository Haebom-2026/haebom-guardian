import 'package:material_ui/material_ui.dart';

import '../../app/dependencies.dart';
import '../../app/theme.dart';
import '../../widgets/common.dart';

/// 알림 권한은 운영체제가 다시 물어볼 기회를 거의 주지 않는다 (iPhone은 한 번, Android는 두 번 거절하면 끝).
/// 그래서 권한 창을 띄우기 **전에** 왜 필요한지 먼저 설명하고, 꺼져 있으면 홈에서 계속 알려 준다.
///
/// 앱 시작 시 호출: 이미 허용됐거나 안내를 본 적이 있으면 아무것도 하지 않는다.
Future<void> showNotificationIntroIfNeeded(AppDependencies deps) async {
  if (await deps.notifications.refreshPermission()) return;
  if (deps.settings.notificationIntroDone) return;
  final nav = deps.navigatorKey.currentState;
  if (nav == null) return;
  await nav.push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const NotificationIntroScreen()));
  // "알림 받기"·"나중에 할게요"·뒤로 가기 어느 쪽이든 다시 보여 주지 않는다 (이후는 홈 안내)
  deps.settings.notificationIntroDone = true;
}

/// 첫 실행 알림 안내: 어떤 알림이 오는지, 무엇은 받지 않는지 설명한 뒤 권한 창을 띄운다.
class NotificationIntroScreen extends StatelessWidget {
  const NotificationIntroScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final deps = AppScope.of(context);
    final k = HaebomTokens.of(context);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Space.page, 40, Space.page, 24),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(Icons.notifications_active_rounded, size: 34, color: k.text),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('가족이 도움을 청하면\n바로 알려 드릴게요', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Text('알림을 켜 두어야 앱을 열지 않아도 바로 알 수 있어요.', style: t.bodyMedium?.copyWith(color: k.textSub)),
                  const SizedBox(height: 28),
                  CardGroup(
                    children: [
                      _Item(
                        icon: Icons.sos_rounded,
                        color: k.dangerText,
                        background: k.dangerBg,
                        title: 'SOS · 사기 의심',
                        body: '가족이 긴급 도움을 요청했을 때',
                      ),
                      const RowDivider(),
                      _Item(
                        icon: Icons.support_rounded,
                        color: k.cautionText,
                        background: k.cautionBg,
                        title: '도움이 필요할 때',
                        body: '앱을 쓰다가 막혀 도움이 필요할 수 있을 때',
                      ),
                      const RowDivider(),
                      _Item(
                        icon: Icons.verified_user_outlined,
                        color: k.text,
                        background: Theme.of(context).colorScheme.secondaryContainer,
                        title: '진행 승인 요청',
                        body: '도우미가 계속 진행해도 되는지 물어볼 때',
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lock_outline_rounded, size: 18, color: k.textSub),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '가족이 동의한 알림만 와요. 비밀번호·화면 내용·위치는 받지 않아요.',
                          style: t.bodySmall?.copyWith(color: k.textSub),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.page, 8, Space.page, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '다음 화면에서 "허용"을 눌러 주세요.',
                    textAlign: TextAlign.center,
                    style: t.bodySmall?.copyWith(color: k.textSub),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    key: const Key('notification_intro_allow'),
                    onPressed: () async {
                      await deps.notifications.requestPermission();
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: const Text('알림 받기'),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    key: const Key('notification_intro_later'),
                    onPressed: () async {
                      await deps.notifications.refreshPermission();
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: const Text('나중에 할게요'),
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

class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.color,
    required this.background,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final Color color;
  final Color background;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.page, vertical: 14),
      child: Row(
        children: [
          IconBadge(icon, color: color, background: background),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(body, style: t.bodySmall?.copyWith(color: HaebomTokens.of(context).textSub)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 홈 맨 위: 알림 권한이 꺼져 있으면 계속 보여 준다. 앱으로 돌아올 때마다 다시 확인한다 (휴대폰 설정에서 켰을 수 있음).
class NotificationOffBanner extends StatefulWidget {
  const NotificationOffBanner({super.key});

  @override
  State<NotificationOffBanner> createState() => _NotificationOffBannerState();
}

class _NotificationOffBannerState extends State<NotificationOffBanner> {
  AppLifecycleListener? _lifecycle;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_lifecycle != null) return;
    final n = AppScope.of(context).notifications;
    if (n.permission.value == null) n.refreshPermission();
    _lifecycle = AppLifecycleListener(onResume: n.refreshPermission);
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = AppScope.of(context).notifications;
    final k = HaebomTokens.of(context);
    final t = Theme.of(context).textTheme;
    return ValueListenableBuilder<bool?>(
      valueListenable: n.permission,
      builder: (context, granted, _) {
        if (granted != false) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(Space.page - 4, 4, Space.page - 4, Space.gap),
          child: Container(
            key: const Key('notification_off_banner'),
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
            decoration: BoxDecoration(color: k.dangerBg, borderRadius: BorderRadius.circular(Space.cardRadius)),
            child: Row(
              children: [
                IconBadge(Icons.notifications_off_rounded, color: k.dangerText, background: k.card),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '알림이 꺼져 있어요',
                        style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: k.dangerText),
                      ),
                      const SizedBox(height: 2),
                      Text('가족이 도움을 요청해도 휴대폰에 알림이 오지 않아요.', style: t.bodySmall?.copyWith(color: k.text)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('notification_off_turn_on'),
                  style: FilledButton.styleFrom(
                    backgroundColor: k.dangerText,
                    foregroundColor: k.card,
                    minimumSize: const Size(64, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onPressed: n.turnOn,
                  child: const Text('켜기'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
