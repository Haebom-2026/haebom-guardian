import 'package:material_ui/material_ui.dart';

import '../app/dependencies.dart';
import 'approvals/approvals_screen.dart';
import 'family/family_screen.dart';
import 'home/home_screen.dart';
import 'notifications/notifications_screen.dart';

/// 하단 네비게이션: 홈 · 알림 · 승인 · 가족
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final deps = AppScope.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: deps.tabIndex,
      builder: (context, index, _) => Scaffold(
        body: IndexedStack(
          index: index,
          children: const [HomeScreen(), NotificationsScreen(), ApprovalsScreen(), FamilyScreen()],
        ),
        bottomNavigationBar: ListenableBuilder(
          listenable: deps.store,
          builder: (context, _) {
            final unread = deps.store.unreadCount();
            final pending = deps.store.pendingCount();
            return NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => deps.tabIndex.value = i,
              destinations: [
                const NavigationDestination(
                    icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: '홈'),
                NavigationDestination(
                  icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.notifications_none_rounded)),
                  selectedIcon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.notifications_rounded)),
                  label: '알림',
                  tooltip: unread > 0 ? '알림, 확인 전 $unread개' : '알림',
                ),
                NavigationDestination(
                  icon: Badge(isLabelVisible: pending > 0, label: Text('$pending'), child: const Icon(Icons.verified_user_outlined)),
                  selectedIcon: Badge(isLabelVisible: pending > 0, label: Text('$pending'), child: const Icon(Icons.verified_user_rounded)),
                  label: '승인',
                  tooltip: pending > 0 ? '승인, 대기 $pending건' : '승인',
                ),
                const NavigationDestination(
                    icon: Icon(Icons.people_outline_rounded), selectedIcon: Icon(Icons.people_rounded), label: '가족'),
              ],
            );
          },
        ),
      ),
    );
  }
}
