import 'package:material_ui/material_ui.dart';

import '../../app/dependencies.dart';
import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../models/family_link.dart';
import '../../repositories/guardian_repository.dart';
import '../../utils/formatters.dart';
import '../../widgets/common.dart';

class FamilyScreen extends StatelessWidget {
  const FamilyScreen({super.key});

  Future<void> _disconnect(BuildContext context, FamilyLink link) async {
    final deps = AppScope.of(context);
    final ok = await confirmDialog(
      context,
      title: '${link.displayName}와(과)의 연결을 해제할까요?',
      message: '연결을 해제하면 ${link.displayName}의 알림과 승인 요청을 더 이상 받을 수 없고, '
          '기존 내역도 볼 수 없습니다. 다시 연결하려면 새 연결 코드가 필요합니다.',
      confirmLabel: '연결 해제',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await deps.repository.disconnect(link.elderId);
      if (context.mounted) showMessage(context, '${link.displayName}와(과)의 연결을 해제했습니다.');
    } on RepositoryException catch (e) {
      if (context.mounted) showMessage(context, e.userMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).store;
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('가족')),
      body: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final links = store.links;
            return ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.page, 4, Space.page, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('연결된 가족 ${links.length}명', style: t.textTheme.titleLarge?.copyWith(fontSize: 22)),
                      const SizedBox(height: 2),
                      Text('한 가족에게 여러 보호자가 함께 연결될 수 있습니다.', style: t.textTheme.bodySmall),
                    ],
                  ),
                ),
                if (links.isEmpty)
                  const EmptyState(
                    icon: Icons.people_outline_rounded,
                    title: '연결된 가족이 없습니다',
                    message: '가족의 해봄 앱 → 가족 연결에서 6자리 코드를 받아 입력해 주세요.',
                  ),
                if (links.isNotEmpty)
                  CardGroup(children: [
                    for (final (i, l) in links.indexed) ...[
                      if (i > 0) const Divider(indent: Space.page + 58, endIndent: Space.page),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(Space.page, 14, Space.page - 12, 14),
                        child: Row(
                          children: [
                            FamilyAvatar(avatarText(l.elderName, fallback: l.displayName), radius: 24),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(l.displayName, style: t.textTheme.titleSmall?.copyWith(fontSize: 17)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${l.elderName} · ${formatDateTime(l.connectedAt, store.now())} 연결',
                                    style: t.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            // 연결 해제는 되돌리기 어려워 바로 보이는 버튼 대신 메뉴 안에 둔다 (확인 시트 유지)
                            PopupMenuButton<String>(
                              tooltip: '${l.displayName} 메뉴',
                              icon: const Icon(Icons.more_vert_rounded),
                              onSelected: (v) {
                                if (v == 'disconnect') _disconnect(context, l);
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'disconnect',
                                  child: Row(
                                    children: [
                                      Icon(Icons.link_off_rounded, color: Theme.of(context).colorScheme.error),
                                      const SizedBox(width: 10),
                                      Text('연결 해제', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ]),
                const SizedBox(height: Space.section),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.page),
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pushNamed(context, AppRoutes.connectFamily),
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('가족 연결'),
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
