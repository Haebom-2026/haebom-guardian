import 'package:material_ui/material_ui.dart';

import '../screens/home_shell.dart';
import 'dependencies.dart';
import 'routes.dart';
import 'theme.dart';

class HaebomFamilyApp extends StatelessWidget {
  const HaebomFamilyApp({super.key, required this.deps});

  final AppDependencies deps;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      deps: deps,
      child: MaterialApp(
        title: '해봄 가족',
        debugShowCheckedModeBanner: false,
        navigatorKey: deps.navigatorKey,
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        themeMode: ThemeMode.system,
        locale: const Locale('ko', 'KR'),
        supportedLocales: const [Locale('ko', 'KR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        onGenerateRoute: AppRoutes.onGenerateRoute,
        builder: (context, child) {
          // 시스템 글자 크기를 존중하되, 레이아웃이 무너지지 않도록 상한을 둔다.
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(
              textScaler: mq.textScaler.clamp(minScaleFactor: 1.0, maxScaleFactor: 1.5),
            ),
            child: child!,
          );
        },
        home: const HomeShell(),
      ),
    );
  }
}
