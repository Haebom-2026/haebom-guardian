package com.yju.haebom.guardian_app

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 알림 권한을 앱에서 더 물어볼 수 없을 때 휴대폰 설정의 이 앱 알림 화면을 연다
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "haebom/settings").setMethodCallHandler { call, result ->
            if (call.method != "openNotificationSettings") return@setMethodCallHandler result.notImplemented()
            val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            try {
                startActivity(intent)
            } catch (e: Exception) {
                startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null)))
            }
            result.success(null)
        }
    }
}
