import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class DashScopeException implements Exception {
  DashScopeException(this.code, this.message, [this.hint]);

  final String code;
  final String message;
  final String? hint;

  @override
  String toString() {
    final h = hint == null ? '' : '\n\n👉 $hint';
    return '$code：$message$h';
  }
}

String? _hintFor(String code, String message) {
  final all = '$code $message';
  if (all.contains('InvalidApiKey') || all.contains('Invalid API-key')) {
    return 'Key 不对或不属于这个服务地址。确认 Key 和「服务地址」来自同一个控制台（百炼通用 Key → dashscope.aliyuncs.com；专有网关 Key → 那个网关的域名）。';
  }
  if (all.contains('Unauthorized') || all.contains('AccessDenied')) {
    return '这个 Key 没有该模型的权限，去百炼控制台开通模型';
  }
  if (all.contains('ModelNotFound') || all.contains('model not exist')) {
    return '模型名不对，去设置里核对（例如 wan3.0-video）';
  }
  if (all.contains('InvalidParameter')) {
    return '参数不合法：去设置的「高级参数」里按官方示例调整，或改小尺寸/时长';
  }
  if (all.contains('Throttling') || all.contains('Requests rate limit')) {
    return '触发限流了，等几分钟再试';
  }
  if (all.contains('DataInspection')) {
    return '内容审核没通过，换个说法再试';
  }
  if (all.contains('Arrearage')) {
    return '账户欠费，去充值';
  }
  if (all.contains('NotFound') || all.contains('404') || all.contains('No match')) {
    return '服务地址不对：视频接口是「域名 + /api/v1」，不是 /compatible-mode/v1。点设置里的「测试连接」看具体哪一段不通。';
  }
  if (all.contains('timeout') || all.contains('Timeout')) {
    return '网络超时，检查手机网络后重试';
  }
  return null;
}

/// 一条连通性探测结果
class ProbeResult {
  ProbeResult({
    required this.name,
    required this.url,
    this.status,
    this.ok = false,
    this.detail = '',
  });

  final String name;
  final String url;
  final int? status;
  final bool ok;
  final String detail;

  String get line =>
      '${ok ? '✓' : '✗'} $name   HTTP $status\n    $url\n    $detail';
}

class DashScope {
  DashScope(this._client, {String? baseUrl})
      : _base = normalizeBase(baseUrl ?? defaultBase);

  final http.Client _client;

  /// 百炼（DashScope）通用地址
  static const String defaultBase = 'https://dashscope.aliyuncs.com/api/v1';

  static const String _videoPath =
      '/services/aigc/video-generation/video-synthesis';

  final String _base;

  String get baseUrl => _base;

  /// 把用户粘进来的各种地址规整成视频接口用的 /api/v1 形式
  ///
  /// 支持：
  ///   https://dashscope.aliyuncs.com                     → …/api/v1
  ///   https://dashscope.aliyuncs.com/compatible-mode/v1  → …/api/v1
  ///   https://xxx.maas.aliyuncs.com/compatible-mode/v1   → …/api/v1
  ///   https://xxx.maas.aliyuncs.com/api/v1               → 原样
  static String normalizeBase(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return defaultBase;
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'https://$s';
    }
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    // 控制台给的 OpenAI 兼容地址 → 换成同主机的 DashScope 原生前缀
    for (final suffix in <String>[
      '/compatible-mode/v1',
      '/compatible-mode',
    ]) {
      if (s.endsWith(suffix)) {
        s = s.substring(0, s.length - suffix.length);
        break;
      }
    }
    if (s.endsWith('/api/v1')) return s;
    if (s.contains('/api/v1/')) {
      s = s.substring(0, s.indexOf('/api/v1/') + '/api/v1'.length);
      return s;
    }
    return '$s/api/v1';
  }

  /// 只留域名，用来拼 compatible-mode 地址
  String get _root {
    const tail = '/api/v1';
    return _base.endsWith(tail)
        ? _base.substring(0, _base.length - tail.length)
        : _base;
  }

  String get videoUrl => '$_base$_videoPath';

  Map<String, String> _headers(String apiKey, {bool async = false}) =>
      <String, String>{
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        if (async) 'X-DashScope-Async': 'enable',
      };

  /// 提交视频生成任务，返回 task_id
  Future<String> submitVideo({
    required String apiKey,
    required String model,
    required String prompt,
    String? size,
    int? duration,
    Map<String, dynamic>? extraParams,
    Map<String, dynamic>? extraInput,
  }) async {
    final input = <String, dynamic>{'prompt': prompt};
    if (extraInput != null) input.addAll(extraInput);
    final parameters = <String, dynamic>{
      if (size != null && size.isNotEmpty) 'size': size,
      if (duration != null) 'duration': duration,
      if (extraParams != null) ...extraParams,
    };
    final payload = <String, dynamic>{
      'model': model,
      'input': input,
      'parameters': parameters,
    };

    http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse(videoUrl),
            headers: _headers(apiKey, async: true),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw DashScopeException('NetworkTimeout', '提交任务超时', '检查手机网络后重试');
    } on SocketException catch (e) {
      throw DashScopeException('NetworkError', e.message, '手机连不上该服务地址，检查网络/域名');
    }

    Map<String, dynamic>? body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      body = null;
    }

    final output = body?['output'] as Map<String, dynamic>?;
    final taskId = output?['task_id'] as String?;
    if (res.statusCode == 200 && taskId != null) return taskId;

    final code =
        (body?['code'] ?? output?['code'] ?? 'HTTP${res.statusCode}').toString();
    final msg = (body?['message'] ?? output?['message'] ?? res.body).toString();
    throw DashScopeException(code, msg, _hintFor(code, msg));
  }

  /// 轮询直到拿到视频地址
  Future<String> waitForVideo({
    required String apiKey,
    required String taskId,
    Duration timeout = const Duration(minutes: 25),
    void Function(String status, int elapsedSec)? onTick,
  }) async {
    final started = DateTime.now();
    var lastStatus = 'PENDING';
    while (DateTime.now().difference(started) < timeout) {
      await Future<void>.delayed(const Duration(seconds: 6));
      final elapsed = DateTime.now().difference(started).inSeconds;
      http.Response res;
      try {
        res = await _client
            .get(Uri.parse('$_base/tasks/$taskId'), headers: _headers(apiKey))
            .timeout(const Duration(seconds: 40));
      } on TimeoutException {
        onTick?.call(lastStatus, elapsed);
        continue;
      }
      Map<String, dynamic>? body;
      try {
        body = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {
        body = null;
      }
      final output =
          body?['output'] as Map<String, dynamic>? ?? <String, dynamic>{};
      final status = (output['task_status'] ?? '?').toString();
      lastStatus = status;
      onTick?.call(status, elapsed);

      if (status == 'SUCCEEDED') {
        String? url = output['video_url'] as String?;
        final results = output['results'] as List?;
        if (url == null && results != null && results.isNotEmpty) {
          final first = results.first;
          if (first is Map) url = first['url'] as String?;
        }
        if (url != null && url.isNotEmpty) return url;
        throw DashScopeException('NoVideoUrl', '任务成功但没返回视频地址：${res.body}');
      }
      if (status == 'FAILED' || status == 'CANCELED') {
        final code = (output['code'] ?? status).toString();
        final msg = (output['message'] ?? '任务失败').toString();
        throw DashScopeException(code, msg, _hintFor(code, msg));
      }
    }
    throw DashScopeException(
      'Timeout',
      '等了 ${timeout.inMinutes} 分钟还没出片（最后状态 $lastStatus）',
      '可以稍后点「重新生成」再试，或把时长调小',
    );
  }

  /// 下载视频到本地文件，返回字节数
  Future<int> downloadTo({
    required String url,
    required String filePath,
    void Function(int received, int total)? onProgress,
  }) async {
    final req = http.Request('GET', Uri.parse(url));
    final streamed = await _client.send(req);
    if (streamed.statusCode != 200) {
      throw DashScopeException(
        'DownloadFailed',
        'HTTP ${streamed.statusCode}',
        '视频链接可能已过期，重新生成一次',
      );
    }
    final total = streamed.contentLength ?? 0;
    final file = File(filePath);
    await file.parent.create(recursive: true);
    final sink = file.openWrite();
    var received = 0;
    await for (final chunk in streamed.stream) {
      sink.add(chunk);
      received += chunk.length;
      onProgress?.call(received, total);
    }
    await sink.flush();
    await sink.close();
    return received;
  }

  // ---------------------------------------------------------------------------
  // 连通性诊断（不花钱：只查任务、只发一次极短的文本请求）
  // ---------------------------------------------------------------------------

  Future<List<ProbeResult>> diagnose({required String apiKey}) async {
    return <ProbeResult>[
      await _probeTaskApi(apiKey),
      await _probeChatApi(apiKey),
    ];
  }

  /// GET /tasks/<不存在的 id>：401 = Key 无效；其它状态说明 Key 被这个地址接受了
  Future<ProbeResult> _probeTaskApi(String apiKey) async {
    final url = '$_base/tasks/diag-probe';
    try {
      final res = await _client
          .get(Uri.parse(url), headers: _headers(apiKey))
          .timeout(const Duration(seconds: 25));
      final parsed = _parse(res);
      final code = (parsed?['code'] ?? '').toString();
      final msg = (parsed?['message'] ?? res.body).toString();
      final authBad = res.statusCode == 401 ||
          res.statusCode == 403 ||
          code.contains('InvalidApiKey') ||
          code.contains('Unauthorized');
      return ProbeResult(
        name: '视频接口（任务查询）',
        url: url,
        status: res.statusCode,
        ok: !authBad,
        detail: authBad
            ? 'Key 被这个地址拒绝：$code $msg'
            : '地址通、Key 被接受（$code ${msg.length > 60 ? msg.substring(0, 60) : msg}）',
      );
    } catch (e) {
      return ProbeResult(
        name: '视频接口（任务查询）',
        url: url,
        detail: '连不上：$e',
      );
    }
  }

  /// POST compatible-mode/chat/completions：验证「这个 Key 是文本接口认的」
  Future<ProbeResult> _probeChatApi(String apiKey) async {
    final url = '$_root/compatible-mode/v1/chat/completions';
    try {
      final res = await _client
          .post(
            Uri.parse(url),
            headers: _headers(apiKey),
            body: jsonEncode(<String, dynamic>{
              'model': 'qwen-turbo',
              'messages': <Map<String, String>>[
                <String, String>{'role': 'user', 'content': '回 ok'},
              ],
              'max_tokens': 4,
            }),
          )
          .timeout(const Duration(seconds: 30));
      final parsed = _parse(res);
      final ok = res.statusCode == 200;
      final err = parsed?['error'];
      final detail = ok
          ? '文本接口可用，返回正常'
          : (err is Map
              ? '${err['code']} ${err['message']}'
              : (parsed?['message'] ?? res.body).toString());
      return ProbeResult(
        name: '兼容模式（文本模型）',
        url: url,
        status: res.statusCode,
        ok: ok,
        detail: detail.length > 160 ? detail.substring(0, 160) : detail,
      );
    } catch (e) {
      return ProbeResult(name: '兼容模式（文本模型）', url: url, detail: '连不上：$e');
    }
  }

  Map<String, dynamic>? _parse(http.Response res) {
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // ignore
    }
    return null;
  }
}
