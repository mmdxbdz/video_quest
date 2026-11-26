import 'package:flutter/material.dart';

import '../models.dart';
import '../runner.dart';
import '../store.dart';
import 'job_screen.dart';

class NewJobScreen extends StatefulWidget {
  const NewJobScreen({super.key});

  @override
  State<NewJobScreen> createState() => _NewJobScreenState();
}

class _NewJobScreenState extends State<NewJobScreen> {
  final TextEditingController _scriptCtrl = TextEditingController();
  late final TextEditingController _styleCtrl;
  final List<TextEditingController> _shotCtrls = <TextEditingController>[];
  bool _split = false;

  @override
  void initState() {
    super.initState();
    _styleCtrl =
        TextEditingController(text: AppStore.instance.settings.styleSuffix);
  }

  @override
  void dispose() {
    _scriptCtrl.dispose();
    _styleCtrl.dispose();
    for (final c in _shotCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _doSplit() {
    final text = _scriptCtrl.text.trim();
    if (text.isEmpty) {
      _toast('先把稿子粘进来');
      return;
    }
    final maxShots = AppStore.instance.settings.maxShots;
    var chunks = splitScript(text);
    if (chunks.length > maxShots) {
      chunks = chunks.take(maxShots).toList();
    }
    for (final c in _shotCtrls) {
      c.dispose();
    }
    _shotCtrls
      ..clear()
      ..addAll(chunks.map((e) => TextEditingController(text: e)));
    setState(() => _split = true);
    if (chunks.length >= maxShots) {
      _toast('稿子较长，按设置只取前 $maxShots 个镜头（可在设置里调大）');
    }
  }

  void _start() {
    if (JobRunner.instance.isRunning) {
      _toast('有任务正在生成，等它跑完再开新任务（同时跑会重复扣费）');
      return;
    }
    if (_shotCtrls.isEmpty) {
      _toast('先拆分镜头');
      return;
    }
    final style = _styleCtrl.text.trim();
    final shots = _shotCtrls
        .map((c) => Shot(prompt: buildPrompt(c.text, style)))
        .toList();
    if (shots.isEmpty) {
      _toast('没有可用的镜头');
      return;
    }
    final job = Job(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      script: _scriptCtrl.text.trim(),
      shots: shots,
      createdAt: DateTime.now(),
    );
    AppStore.instance.addJob(job);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
          builder: (_) => JobScreen(job: job, autoStart: true)),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('写稿出片')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: <Widget>[
          const Text('① 粘贴稿子', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _scriptCtrl,
            minLines: 5,
            maxLines: 12,
            decoration: const InputDecoration(
              hintText: '凌晨四点的菜市场，第一盏灯亮起……\n\n按句号/换行自动切成镜头',
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 20),
          const Text('② 统一风格后缀', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _styleCtrl,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: '35mm胶片质感，浅景深，电影感调色，缓慢推镜',
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _doSplit,
            icon: const Icon(Icons.content_cut),
            label: const Text('拆成镜头'),
          ),
          if (_split) ...<Widget>[
            const SizedBox(height: 24),
            Row(
              children: <Widget>[
                Text('③ 检查镜头（${_shotCtrls.length} 个）',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(
                  '可逐条改文字',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.5)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < _shotCtrls.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: _shotCtrls[i],
                  minLines: 1,
                  maxLines: 4,
                  style: const TextStyle(fontSize: 13.5),
                  decoration: InputDecoration(
                    prefixIcon: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text('${i + 1}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _start,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text('开始生成（${_shotCtrls.length} 个镜头）'),
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
            ),
            const SizedBox(height: 10),
            Text(
              '每个镜头会调用一次视频生成模型，按实际用量计费。',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11.5, color: Colors.white.withValues(alpha: 0.45)),
            ),
          ],
        ],
      ),
    );
  }
}
