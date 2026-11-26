import 'package:material_ui/material_ui.dart';

import '../../app/dependencies.dart';
import '../../app/routes.dart';
import '../../models/approval_request.dart';
import '../../widgets/common.dart';

class ApprovalsScreen extends StatelessWidget {
  const ApprovalsScreen({super.key});

  static const _tabs = ApprovalStatus.values;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).store;
    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('도우미 진행 승인'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: ListenableBuilder(
              listenable: store,
              builder: (context, _) => TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  for (final s in _tabs)
                    Tab(
                      text: s == ApprovalStatus.pending
                          ? '${s.label} ${store.pendingCount(elderId: store.selectedElderId)}'
                          : s.label,
                    ),
                ],
              ),
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: ListenableBuilder(
            listenable: store,
            builder: (context, _) => Column(
              children: [
                const SizedBox(height: 8),
                FamilyFilterBar(store: store),
                Expanded(
                  child: TabBarView(
                    children: [
                      for (final s in _tabs) _ApprovalList(status: s),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ApprovalList extends StatelessWidget {
  const _ApprovalList({required this.status});
  final ApprovalStatus status;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).store;
    final items = store.approvalsFor(elderId: store.selectedElderId, status: status);
    if (items.isEmpty) {
      return ListView(children: [
        EmptyState(
          icon: Icons.verified_user_outlined,
          title: status == ApprovalStatus.pending ? '승인 대기 내역이 없습니다' : "'${status.label}' 내역이 없습니다",
          message: status == ApprovalStatus.pending
              ? '가족이 해봄 도우미 진행에 대한 확인을 요청하면 이곳에 표시됩니다.'
              : null,
        ),
      ]);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => ApprovalCard(
        request: items[i],
        store: store,
        onTap: () => Navigator.pushNamed(context, AppRoutes.approvalDetail, arguments: items[i].id),
      ),
    );
  }
}
