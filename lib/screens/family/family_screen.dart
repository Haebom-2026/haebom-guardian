import 'package:material_ui/material_ui.dart';

import '../../app/dependencies.dart';
import '../../app/routes.dart';
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(context, AppRoutes.connectFamily),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('가족 연결'),
      ),
      body: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final links = store.links;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                Text('연결된 가족 ${links.length}명', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('한 가족에게 여러 보호자가 함께 연결될 수 있습니다.',
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                if (links.isEmpty)
                  const Card(
                    child: EmptyState(
                      icon: Icons.people_outline_rounded,
                      title: '연결된 가족이 없습니다',
                      message: '가족의 해봄 앱 → 가족 연결에서 6자리 코드를 받아 입력해 주세요.',
                    ),
                  ),
                for (final l in links)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                        child: Row(
                          children: [
                            FamilyAvatar(l.displayName),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(l.displayName,
                                      style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                                  Text(l.elderName, style: t.textTheme.bodyMedium),
                                  Text('${formatDateTime(l.connectedAt, store.now())} 연결',
                                      style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: '${l.displayName} 연결 해제',
                              icon: const Icon(Icons.link_off_rounded),
                              onPressed: () => _disconnect(context, l),
                            ),
                          ],
                        ),
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
