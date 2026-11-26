import 'package:material_ui/material_ui.dart';

import '../app/dependencies.dart';
import 'approvals/approvals_screen.dart';
import 'challenges/challenges_screen.dart';
import 'family/family_screen.dart';
import 'home/home_screen.dart';
import 'notifications/notifications_screen.dart';

/// 하단 네비게이션: 홈 · 알림 · 승인 · (도전) · 가족
/// 도전 탭은 💡 제안 단계라 저장소가 지원할 때(Mock 모드)만 보인다. 서버 모드에서는 4칸.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  /// 도전 탭 위치 (도전을 지원할 때만 있음)
  static const challengesTab = 3;

  @override
  Widget build(BuildContext context) {
    final deps = AppScope.of(context);
    final challenges = deps.store.supportsChallenges;
    return ValueListenableBuilder<int>(
      valueListenable: deps.tabIndex,
      builder: (context, index, _) => Scaffold(
        body: IndexedStack(
          index: index,
          children: [
            const HomeScreen(),
            const NotificationsScreen(),
            const ApprovalsScreen(),
            if (challenges) const ChallengesScreen(),
            const FamilyScreen(),
          ],
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
          ),
          child: ListenableBuilder(
            listenable: deps.store,
            builder: (context, _) {
              final unread = deps.store.unreadCount();
              final pending = deps.store.pendingCount();
              final me = deps.store.guardianId;
              // 칭찬을 기다리는 도전 수 (해냈는데 내가 아직 칭찬하지 않음)
              final cheers = deps.store.challenges.where((c) => c.isDone && !c.cheeredBy(me)).length;
              return NavigationBar(
                selectedIndex: index,
                onDestinationSelected: (i) => deps.tabIndex.value = i,
                destinations: [
                  const NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: '홈',
                  ),
                  NavigationDestination(
                    icon: Badge(
                      isLabelVisible: unread > 0,
                      label: Text('$unread'),
                      child: const Icon(Icons.notifications_none_rounded),
                    ),
                    selectedIcon: Badge(
                      isLabelVisible: unread > 0,
                      label: Text('$unread'),
                      child: const Icon(Icons.notifications_rounded),
                    ),
                    label: '알림',
                    tooltip: unread > 0 ? '알림, 확인 전 $unread개' : '알림',
                  ),
                  NavigationDestination(
                    icon: Badge(
                      isLabelVisible: pending > 0,
                      label: Text('$pending'),
                      child: const Icon(Icons.verified_user_outlined),
                    ),
                    selectedIcon: Badge(
                      isLabelVisible: pending > 0,
                      label: Text('$pending'),
                      child: const Icon(Icons.verified_user_rounded),
                    ),
                    label: '승인',
                    tooltip: pending > 0 ? '승인, 대기 $pending건' : '승인',
                  ),
                  if (challenges)
                    NavigationDestination(
                      icon: Badge(
                        isLabelVisible: cheers > 0,
                        backgroundColor: Theme.of(context).colorScheme.primary, // 급한 일이 아니라 즐거운 소식이라 빨강 대신
                        label: Text('$cheers'),
                        child: const Icon(Icons.flag_outlined),
                      ),
                      selectedIcon: Badge(
                        isLabelVisible: cheers > 0,
                        backgroundColor: Theme.of(context).colorScheme.primary, // 급한 일이 아니라 즐거운 소식이라 빨강 대신
                        label: Text('$cheers'),
                        child: const Icon(Icons.flag_rounded),
                      ),
                      label: '도전',
                      tooltip: cheers > 0 ? '도전, 칭찬 대기 $cheers건' : '도전',
                    ),
                  const NavigationDestination(
                    icon: Icon(Icons.people_outline_rounded),
                    selectedIcon: Icon(Icons.people_rounded),
                    label: '가족',
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
