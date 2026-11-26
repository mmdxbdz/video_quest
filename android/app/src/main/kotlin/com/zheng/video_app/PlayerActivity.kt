package com.zheng.video_app

import android.app.Activity
import android.os.Bundle
import android.view.WindowManager
import android.widget.MediaController
import android.widget.VideoView
import java.io.File

/** 极简全屏视频播放页：只用系统 VideoView，不依赖任何插件 */
class PlayerActivity : Activity() {
    companion object {
        const val EXTRA_PATH = "path"
    }

    private var videoView: VideoView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val path = intent.getStringExtra(EXTRA_PATH)
        if (path.isNullOrBlank() || !File(path).exists()) {
            finish()
            return
        }
        val vv = VideoView(this)
        videoView = vv
        setContentView(vv)
        val controller = MediaController(this)
        controller.setAnchorView(vv)
        vv.setMediaController(controller)
        vv.setOnPreparedListener { mp ->
            mp.isLooping = true
            vv.start()
        }
        vv.setOnErrorListener { _, _, _ -> true }
        vv.setVideoPath(path)
        vv.requestFocus()
    }

    override fun onDestroy() {
        videoView?.stopPlayback()
        super.onDestroy()
    }
}
