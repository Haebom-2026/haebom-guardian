import 'package:material_ui/material_ui.dart';

import '../../app/dependencies.dart';
import '../../app/routes.dart';
import '../../widgets/common.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _unreadOnly = false;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).store;
    return Scaffold(
      appBar: AppBar(
        title: const Text('알림'),
        actions: [
          ListenableBuilder(
            listenable: store,
            builder: (context, _) => TextButton(
              onPressed: store.unreadCount(elderId: store.selectedElderId) == 0
                  ? null
                  : () async {
                      final ok = await confirmDialog(context,
                          title: '모두 확인',
                          message: '확인 전 알림을 모두 확인 처리할까요?\n가족의 해봄 앱에 "확인했어요"로 표시될 수 있습니다.',
                          confirmLabel: '모두 확인');
                      if (ok) await store.repository.markAllNotificationsRead(elderId: store.selectedElderId);
                    },
              child: const Text('모두 확인'),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final items = store.notificationsFor(elderId: store.selectedElderId, unreadOnly: _unreadOnly);
            return Column(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('전체'),
                        selected: !_unreadOnly,
                        onSelected: (_) => setState(() => _unreadOnly = false),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: Text('확인 전 ${store.unreadCount(elderId: store.selectedElderId)}'),
                        selected: _unreadOnly,
                        onSelected: (_) => setState(() => _unreadOnly = true),
                      ),
                    ],
                  ),
                ),
                FamilyFilterBar(store: store),
                const SizedBox(height: 8),
                Expanded(
                  child: items.isEmpty
                      ? ListView(children: [
                          EmptyState(
                            icon: Icons.notifications_none_rounded,
                            title: _unreadOnly ? '확인 전 알림이 없습니다' : '알림이 없습니다',
                            message: '가족이 민감한 서비스 이용 알림에 동의하면 이곳에 표시됩니다.',
                          ),
                        ])
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (context, i) => NotificationTile(
                            item: items[i],
                            store: store,
                            onTap: () =>
                                Navigator.pushNamed(context, AppRoutes.notificationDetail, arguments: items[i].id),
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
