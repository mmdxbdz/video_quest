import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';

import '../models.dart';
import '../native.dart';
import '../runner.dart';
import '../store.dart';

class JobScreen extends StatefulWidget {
  const JobScreen({super.key, required this.job, this.autoStart = false});

  final Job job;
  final bool autoStart;

  @override
  State<JobScreen> createState() => _JobScreenState();
}

class _JobScreenState extends State<JobScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startAll());
    }
  }

  /// 始终拿仓库里的那个实例，保证进度是最新的
  Job get job => AppStore.instance.jobs.firstWhere(
        (j) => j.id == widget.job.id,
        orElse: () => widget.job,
      );

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _startAll() async {
    final runner = JobRunner.instance;
    if (runner.isRunning) {
      _toast(runner.isRunningJob(job.id)
          ? '这个任务正在生成中'
          : '已有另一个任务在生成，先等它完成或点停止');
      return;
    }
    for (final s in job.shots) {
      if (s.status == ShotStatus.failed) s.status = ShotStatus.idle;
    }
    try {
      await runner.start(job);
    } catch (e) {
      _toast(e.toString());
    }
    if (!mounted) return;
    _toast(job.doneCount == job.shots.length ? '全部完成 ✅' : '已停止');
  }

  Future<void> _runOne(int index) async {
    final runner = JobRunner.instance;
    if (runner.isRunning) {
      _toast('已有任务在生成，先等它完成或点停止');
      return;
    }
    try {
      await runner.runSingle(job, index);
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<void> _play(int index) async {
    final path = job.shots[index].videoPath;
    if (path == null) return;
    if (!await File(path).exists()) {
      _toast('文件不见了，重新生成一次');
      return;
    }
    try {
      await NativeBridge.playVideo(path);
    } catch (e) {
      _toast('播放失败：$e');
    }
  }

  Future<void> _saveToGallery(int index) async {
    final path = job.shots[index].videoPath;
    if (path == null) return;
    try {
      await Gal.putVideo(path, album: 'AI成片');
      _toast('已存到相册 · AI成片');
    } catch (e) {
      _toast('保存失败：$e');
    }
  }

  Future<void> _saveAll() async {
    final done = job.shots.where((s) => s.status == ShotStatus.done).toList();
    if (done.isEmpty) {
      _toast('还没有完成的镜头');
      return;
    }
    var ok = 0;
    for (final s in done) {
      final p = s.videoPath;
      if (p == null) continue;
      try {
        await Gal.putVideo(p, album: 'AI成片');
        ok++;
      } catch (_) {
        // ignore single failure
      }
    }
    _toast('已保存 $ok 个到相册');
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        AppStore.instance,
        JobRunner.instance,
      ]),
      builder: (context, _) {
        final runner = JobRunner.instance;
        final j = job;
        final total = j.shots.length;
        final done = j.doneCount;
        final failed = j.failedCount;
        final runningHere = runner.isRunningJob(j.id);
        final anyRunning = runner.isRunning;
        return Scaffold(
          appBar: AppBar(
            title: Text(j.title, overflow: TextOverflow.ellipsis),
            actions: <Widget>[
              IconButton(
                tooltip: '全部保存到相册',
                icon: const Icon(Icons.download_outlined),
                onPressed: _saveAll,
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: <Widget>[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text(
                            '$done/$total 完成',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          if (failed > 0) ...<Widget>[
                            const SizedBox(width: 10),
                            Text('· $failed 失败',
                                style: const TextStyle(
                                    fontSize: 12, color: Color(0xFFFF8A80))),
                          ],
                          const Spacer(),
                          if (runningHere)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0x337C9CFF),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  SizedBox(
                                    width: 10,
                                    height: 10,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF7C9CFF)),
                                  ),
                                  SizedBox(width: 6),
                                  Text('运行中',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF7C9CFF))),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // 实时状态：第几个镜头 / 阶段 / 秒数 / 官方任务状态
                      if (runningHere)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _liveLine(runner, total),
                            style: const TextStyle(
                                fontSize: 12.5,
                                height: 1.5,
                                color: Color(0xFFAEBEFF)),
                          ),
                        ),
                      if (runningHere) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(
                          runner.message.isEmpty ? '正在调用视频模型，通常 1~3 分钟出片' : runner.message,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.45)),
                        ),
                      ],
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: total == 0 ? 0 : done / total,
                          minHeight: 6,
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      if (runningHere) ...<Widget>[
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: const LinearProgressIndicator(
                            minHeight: 3,
                            backgroundColor: Colors.transparent,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: anyRunning && !runningHere
                                  ? null
                                  : (runningHere
                                      ? () => runner.cancel()
                                      : _startAll),
                              icon: Icon(runningHere
                                  ? Icons.stop_circle_outlined
                                  : Icons.auto_awesome),
                              label: Text(
                                runningHere
                                    ? '停止（当前镜头跑完就停）'
                                    : (done == total && total > 0
                                        ? '重新生成全部'
                                        : '开始 / 继续生成'),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (anyRunning && !runningHere) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(
                          '另一个任务正在生成，同时只能跑一个，避免重复扣费',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.45)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < j.shots.length; i++) _shotCard(i, runner),
            ],
          ),
        );
      },
    );
  }

  Widget _shotCard(int index, JobRunner runner) {
    final shot = job.shots[index];
    final live = runner.isRunningJob(job.id) && runner.index == index;
    final color = live
        ? const Color(0xFF7C9CFF)
        : switch (shot.status) {
            ShotStatus.idle => Colors.white.withValues(alpha: 0.35),
            ShotStatus.running => const Color(0xFF7C9CFF),
            ShotStatus.done => const Color(0xFF62D6A0),
            ShotStatus.failed => const Color(0xFFFF8A80),
          };
    final label = live ? runner.stageLabel : switch (shot.status) {
        ShotStatus.idle => '未生成',
        ShotStatus.running => '生成中',
        ShotStatus.done => '已完成',
        ShotStatus.failed => '失败',
      };
    final secs = live
        ? runner.elapsedLabel
        : (shot.elapsedMs > 0 ? formatElapsed(shot.elapsedMs) : '');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${index + 1}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: color)),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      secs.isEmpty ? label : '$label · $secs',
                      style: TextStyle(fontSize: 11, color: color),
                    ),
                  ),
                  const Spacer(),
                  if (shot.status == ShotStatus.done)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: '重新生成这一个',
                      icon: const Icon(Icons.refresh, size: 19),
                      onPressed: runner.isRunning ? null : () => _runOne(index),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                shot.prompt,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: Colors.white.withValues(alpha: 0.85)),
              ),
              if (shot.error != null) ...<Widget>[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0x33FF5252),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    shot.error!,
                    style: const TextStyle(fontSize: 11.5, height: 1.5),
                  ),
                ),
              ],
              if (shot.status == ShotStatus.done) ...<Widget>[
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () => _play(index),
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: const Text('播放'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _saveToGallery(index),
                        icon: const Icon(Icons.download_outlined, size: 18),
                        label: const Text('存相册'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _liveLine(JobRunner runner, int total) {
    final parts = <String>[
      '第 ${runner.index + 1}/$total 个',
      runner.stageLabel,
      runner.elapsedLabel,
    ];
    if (runner.taskStatus.isNotEmpty) parts.add('task ${runner.taskStatus}');
    return parts.join(' · ');
  }
}
