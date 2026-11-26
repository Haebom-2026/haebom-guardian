import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../screens/approvals/approval_detail_screen.dart';
import '../screens/developer/developer_screen.dart';
import '../screens/family/connect_family_screen.dart';
import '../screens/notifications/notification_detail_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../services/notification_service.dart';

class AppRoutes {
  static const notificationDetail = '/notification';
  static const approvalDetail = '/approval';
  static const settings = '/settings';
  static const connectFamily = '/family/connect';
  static const developer = '/developer';

  /// 개발자 테스트 화면은 디버그 빌드에서만 허용
  static bool get developerEnabled => kDebugMode;

  static Route<dynamic>? onGenerateRoute(RouteSettings s) {
    Widget? page = switch (s.name) {
      notificationDetail => NotificationDetailScreen(notificationId: s.arguments as String),
      approvalDetail => ApprovalDetailScreen(approvalId: s.arguments as String),
      settings => const SettingsScreen(),
      connectFamily => const ConnectFamilyScreen(),
      developer => developerEnabled ? const DeveloperScreen() : null,
      _ => null,
    };
    if (page == null) return null;
    return MaterialPageRoute<void>(builder: (_) => page, settings: s);
  }

  /// 로컬 알림(향후 FCM) 탭 시 해당 상세 화면으로 이동
  static void openTarget(NavigatorState? nav, AlertTarget target) {
    if (nav == null) return;
    final route = target.kind == AlertTarget.approval ? approvalDetail : notificationDetail;
    nav.pushNamed(route, arguments: target.id);
  }
}
