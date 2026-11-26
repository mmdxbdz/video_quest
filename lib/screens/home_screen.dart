import 'package:flutter/material.dart';

import '../models.dart';
import '../runner.dart';
import '../store.dart';
import 'job_screen.dart';
import 'new_job_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        AppStore.instance,
        JobRunner.instance,
      ]),
      builder: (context, _) {
        final store = AppStore.instance;
        final jobs = store.jobs;
        return Scaffold(
          appBar: AppBar(
            title: const Row(
              children: <Widget>[
                Text('🎬 AI 成片', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            actions: <Widget>[
              IconButton(
                tooltip: '设置',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const SettingsScreen()),
                ),
              ),
            ],
          ),
          body: Column(
            children: <Widget>[
              if (store.apiKey.isEmpty) _keyWarning(context),
              if (JobRunner.instance.isRunning) _runningBanner(context, jobs),
              Expanded(
                child: jobs.isEmpty
                    ? _empty()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        itemCount: jobs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) => _jobCard(context, jobs[i]),
                      ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              if (JobRunner.instance.isRunning) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('有任务正在生成，先等它跑完再写新稿（同时跑会重复扣费）')),
                );
                return;
              }
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const NewJobScreen()),
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('写稿出片'),
          ),
        );
      },
    );
  }

  /// 顶部「正在生成」横幅：离开生成页也能看到进度
  Widget _runningBanner(BuildContext context, List<Job> jobs) {
    final runner = JobRunner.instance;
    final job = jobs.where((j) => j.id == runner.runningJobId).toList();
    final title = job.isEmpty ? '生成中' : job.first.title;
    final done = job.isEmpty ? 0 : job.first.doneCount;
    final total = job.isEmpty
        ? runner.total
        : (job.first.shots.isEmpty ? runner.total : job.first.shots.length);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        color: const Color(0xFF232347),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            if (job.isEmpty) return;
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => JobScreen(job: job.first)),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF7C9CFF)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '正在生成 · $title',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFCBD5FF)),
                      ),
                    ),
                    Text(
                      '$done/$total',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF9FAEFF)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '第 ${runner.index + 1}/$total 个 · ${runner.stageLabel} · ${runner.elapsedLabel}   （点这里看详情）',
                  style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.white.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: total == 0 ? null : done / total,
                    minHeight: 5,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _keyWarning(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF3A2A12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.key_off_outlined, color: Color(0xFFFFC46B)),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              '还没填 API Key，先去设置里粘贴你的阿里云百炼 Key',
              style: TextStyle(color: Color(0xFFFFE0B2), fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('🎥', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 18),
            const Text(
              '把稿子变成电影感视频',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              '点右下角「写稿出片」，粘贴你的稿子，\n自动拆成镜头，逐条生成视频。\n'
              '全程在你手机上跑，不上传任何稿子。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _jobCard(BuildContext context, Job job) {
    final total = job.shots.length;
    final done = job.doneCount;
    final runner = JobRunner.instance;
    final running = runner.isRunningJob(job.id);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => JobScreen(job: job)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      job.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (running)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0x337C9CFF),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '生成中 ${runner.index + 1}/$total',
                        style: const TextStyle(
                            fontSize: 10.5, color: Color(0xFF7C9CFF)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Icon(Icons.movie_outlined,
                      size: 15, color: Colors.white.withValues(alpha: 0.5)),
                  const SizedBox(width: 6),
                  Text(
                    '$done/$total 个镜头',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.6)),
                  ),
                  const Spacer(),
                  Text(
                    '${job.createdAt.month}月${job.createdAt.day}日',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.4)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : done / total,
                  minHeight: 5,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
