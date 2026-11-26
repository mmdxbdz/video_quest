import 'package:flutter/services.dart';

/// 调用原生（Kotlin）能力：全屏播放本地视频
class NativeBridge {
  static const MethodChannel _channel = MethodChannel('video_app/native');

  static Future<void> playVideo(String path) async {
    await _channel.invokeMethod<bool>('playVideo', <String, dynamic>{
      'path': path,
    });
  }
}
