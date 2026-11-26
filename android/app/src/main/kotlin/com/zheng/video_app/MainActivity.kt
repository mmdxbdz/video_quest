package com.zheng.video_app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "video_app/native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "playVideo" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("ARGS", "missing path", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val intent = Intent(this, PlayerActivity::class.java)
                            intent.putExtra(PlayerActivity.EXTRA_PATH, path)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("PLAY_FAIL", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
