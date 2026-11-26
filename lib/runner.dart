import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'dashscope.dart';
import 'models.dart';
import 'store.dart';

/// 一个镜头内部的阶段
enum ShotStage { idle, submitting, queued, generating, downloading, done, failed }

String formatElapsed(int ms) {
  final total = (ms / 1000).floor();
  final m = total ~/ 60;
  final s = total % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// 全局生成器：**跟界面无关**，所以返回首页、锁屏、切后台都不影响进度显示
class JobRunner extends ChangeNotifier {
  JobRunner._();

  static final JobRunner instance = JobRunner._();

  String? _jobId;
  int _index = -1;
  int _total = 0;
  ShotStage _stage = ShotStage.idle;
  String _taskStatus = '';
  int _elapsedMs = 0;
  String _message = '';
  bool _cancelRequested = false;
  Timer? _ticker;

  bool get isRunning => _jobId != null;
  String? get runningJobId => _jobId;
  int get index => _index;
  int get total => _total;
  ShotStage get stage => _stage;
  String get taskStatus => _taskStatus;
  int get elapsedMs => _elapsedMs;
  String get message => _message;
  bool get cancelRequested => _cancelRequested;

  bool isRunningJob(String jobId) => _jobId == jobId;

  String get stageLabel => switch (_stage) {
        ShotStage.idle => '待开始',
        ShotStage.submitting => '提交任务中',
        ShotStage.queued => '已入队排队中',
        ShotStage.generating => '模型生成中',
        ShotStage.downloading => '下载视频中',
        ShotStage.done => '已完成',
        ShotStage.failed => '失败',
      };

  /// 当前镜头的耗时（秒表实时走，不等接口回包）
  String get elapsedLabel => formatElapsed(_elapsedMs);

  void cancel() {
    if (!isRunning) return;
    _cancelRequested = true;
    notifyListeners();
  }

  /// 开始 / 继续一个任务。已经在跑就直接返回。
  Future<void> start(Job job) async {
    if (isRunning) return;
    final store = AppStore.instance;
    if (store.apiKey.isEmpty) {
      throw DashScopeException('NoApiKey', '还没填 API Key', '去设置里粘贴你的 Key');
    }

    _jobId = job.id;
    _total = job.shots.length;
    _cancelRequested = false;
    _message = '';
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isRunning) return;
      if (_stage == ShotStage.submitting ||
          _stage == ShotStage.queued ||
          _stage == ShotStage.generating ||
          _stage == ShotStage.downloading) {
        _elapsedMs += 1000;
        notifyListeners();
      }
    });
    notifyListeners();

    try {
      for (var i = 0; i < job.shots.length; i++) {
        if (_cancelRequested) break;
        if (job.shots[i].status == ShotStatus.done) continue;
        _index = i;
        await _runOne(job, i);
        if (_cancelRequested) break;
      }
    } finally {
      _ticker?.cancel();
      _ticker = null;
      _jobId = null;
      _index = -1;
      _stage = ShotStage.idle;
      _taskStatus = '';
      _elapsedMs = 0;
      notifyListeners();
    }
  }

  /// 只重跑某一个镜头
  Future<void> runSingle(Job job, int index) async {
    if (isRunning) return;
    if (AppStore.instance.apiKey.isEmpty) {
      throw DashScopeException('NoApiKey', '还没填 API Key', '去设置里粘贴你的 Key');
    }
    _jobId = job.id;
    _total = job.shots.length;
    _index = index;
    _cancelRequested = false;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isRunning) return;
      _elapsedMs += 1000;
      notifyListeners();
    });
    notifyListeners();
    try {
      await _runOne(job, index);
    } finally {
      _ticker?.cancel();
      _ticker = null;
      _jobId = null;
      _index = -1;
      _stage = ShotStage.idle;
      _taskStatus = '';
      _elapsedMs = 0;
      notifyListeners();
    }
  }

  Future<Directory> _videoDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/videos');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  ShotStage _stageOf(String status) {
    switch (status) {
      case 'PENDING':
        return ShotStage.queued;
      case 'RUNNING':
        return ShotStage.generating;
      case 'SUCCEEDED':
        return ShotStage.done;
      case 'FAILED':
      case 'CANCELED':
      case 'UNKNOWN':
        return ShotStage.failed;
      default:
        return ShotStage.generating;
    }
  }

  Future<void> _runOne(Job job, int index) async {
    final store = AppStore.instance;
    final key = store.apiKey;
    final shot = job.shots[index];
    final sw = Stopwatch()..start();

    shot.status = ShotStatus.running;
    shot.error = null;
    shot.elapsedMs = 0;
    _stage = ShotStage.submitting;
    _taskStatus = '';
    _elapsedMs = 0;
    notifyListeners();
    await store.updateJob(job);

    final client = http.Client();
    try {
      final s = store.settings;
      final ds = DashScope(client, baseUrl: s.baseUrl);
      final taskId = await ds.submitVideo(
        apiKey: key,
        model: s.model,
        prompt: shot.prompt,
        size: s.size,
        duration: s.duration,
        extraParams: s.extraParams,
      );
      _stage = ShotStage.queued;
      _message = '已提交，task_id $taskId';
      _elapsedMs = sw.elapsedMilliseconds;
      notifyListeners();

      final url = await ds.waitForVideo(
        apiKey: key,
        taskId: taskId,
        onTick: (status, sec) {
          _taskStatus = status;
          _stage = _stageOf(status);
          _elapsedMs = sw.elapsedMilliseconds;
          notifyListeners();
        },
      );

      _stage = ShotStage.downloading;
      _elapsedMs = sw.elapsedMilliseconds;
      notifyListeners();

      final dir = await _videoDir();
      final path = '${dir.path}/${job.id}_$index.mp4';
      await ds.downloadTo(url: url, filePath: path);

      sw.stop();
      shot.status = ShotStatus.done;
      shot.videoPath = path;
      shot.elapsedMs = sw.elapsedMilliseconds;
      _stage = ShotStage.done;
      _elapsedMs = shot.elapsedMs;
    } catch (e) {
      sw.stop();
      shot.status = ShotStatus.failed;
      shot.error = e.toString();
      shot.elapsedMs = sw.elapsedMilliseconds;
      _stage = ShotStage.failed;
      _message = e.toString();
      _elapsedMs = shot.elapsedMs;
    } finally {
      client.close();
      await store.updateJob(job);
      notifyListeners();
    }
  }
}
