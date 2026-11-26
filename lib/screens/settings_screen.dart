import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../dashscope.dart';
import '../store.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _keyCtrl;
  late final TextEditingController _baseCtrl;
  late final TextEditingController _modelCtrl;
  late final TextEditingController _sizeCtrl;
  late final TextEditingController _styleCtrl;
  late final TextEditingController _extraCtrl;
  late int _duration;
  late double _maxShots;
  bool _obscure = true;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    final s = AppStore.instance.settings;
    _keyCtrl = TextEditingController(text: AppStore.instance.apiKey);
    _baseCtrl = TextEditingController(text: s.baseUrl);
    _modelCtrl = TextEditingController(text: s.model);
    _sizeCtrl = TextEditingController(text: s.size);
    _styleCtrl = TextEditingController(text: s.styleSuffix);
    _extraCtrl = TextEditingController(text: s.extraParamsJson);
    _duration = s.duration;
    _maxShots = s.maxShots.toDouble();
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _baseCtrl.dispose();
    _modelCtrl.dispose();
    _sizeCtrl.dispose();
    _styleCtrl.dispose();
    _extraCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final store = AppStore.instance;
    await store.saveApiKey(_keyCtrl.text);
    store.settings
      ..baseUrl = DashScope.normalizeBase(_baseCtrl.text)
      ..model = _modelCtrl.text.trim().isEmpty ? 'wan3.0-video' : _modelCtrl.text.trim()
      ..size = _sizeCtrl.text.trim()
      ..duration = _duration
      ..styleSuffix = _styleCtrl.text.trim()
      ..maxShots = _maxShots.round()
      ..extraParamsJson = _extraCtrl.text.trim();
    await store.saveSettings();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已保存 ✅')));
    Navigator.of(context).pop();
  }

  Future<void> _testConnection() async {
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('先填 API Key')));
      return;
    }
    setState(() => _testing = true);
    final client = http.Client();
    try {
      final ds = DashScope(client, baseUrl: _baseCtrl.text);
      final results = await ds.diagnose(apiKey: key);
      if (!mounted) return;
      final lines = <String>[
        '视频提交地址：',
        ds.videoUrl,
        '',
        ...results.map((r) => r.line),
        '',
        '判断：第一条（视频接口）✓ 就能生成；',
        '两条都 ✗ → Key 和这个地址不是同一家的。',
      ];
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('连接测试'),
          content: SingleChildScrollView(
            child: SelectableText(
              lines.join('\n'),
              style: const TextStyle(fontSize: 11.5, height: 1.6),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('测试失败：$e')));
    } finally {
      client.close();
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          _section('🔑 API Key（只存你手机里）'),
          TextField(
            controller: _keyCtrl,
            obscureText: _obscure,
            decoration: InputDecoration(
              hintText: 'sk-...',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text(
            '存在系统加密存储（Android Keystore）里，不上传、不写进安装包。',
            style: TextStyle(
                fontSize: 11.5, color: Colors.white.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 24),
          _section('🌐 服务地址（视频接口）'),
          TextField(
            controller: _baseCtrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: 'https://dashscope.aliyuncs.com/api/v1',
              helperText: '百炼通用：https://dashscope.aliyuncs.com/api/v1\n'
                  '专有/独享网关：https://你的域名/api/v1\n'
                  '粘 .../compatible-mode/v1 也可以，会自动换成 /api/v1',
              helperMaxLines: 4,
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _testing ? null : _testConnection,
            icon: _testing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.network_check, size: 18),
            label: Text(_testing ? '测试中…（最长约 60 秒）' : '测试连接（不花钱）'),
          ),
          const SizedBox(height: 24),
          _section('🎞 视频模型'),
          TextField(
            controller: _modelCtrl,
            decoration: const InputDecoration(
              hintText: 'wan3.0-video',
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 24),
          _section('📐 画面尺寸'),
          TextField(
            controller: _sizeCtrl,
            decoration: const InputDecoration(
              hintText: '720*1280',
              helperText: '竖屏 720*1280 / 横屏 1280*720',
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 24),
          _section('⏱ 每个镜头时长'),
          SegmentedButton<int>(
            segments: const <ButtonSegment<int>>[
              ButtonSegment<int>(value: 5, label: Text('5 秒')),
              ButtonSegment<int>(value: 6, label: Text('6 秒')),
              ButtonSegment<int>(value: 8, label: Text('8 秒')),
              ButtonSegment<int>(value: 10, label: Text('10 秒')),
            ],
            selected: <int>{_duration},
            onSelectionChanged: (v) => setState(() => _duration = v.first),
          ),
          const SizedBox(height: 24),
          _section('🎨 统一风格后缀（每个镜头都会拼上）'),
          TextField(
            controller: _styleCtrl,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 24),
          _section('🛡 每次最多镜头数（控制花费）'),
          Row(
            children: <Widget>[
              Expanded(
                child: Slider(
                  value: _maxShots,
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: _maxShots.round().toString(),
                  onChanged: (v) => setState(() => _maxShots = v),
                ),
              ),
              SizedBox(
                width: 36,
                child: Text('${_maxShots.round()}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _section('⚙️ 高级参数（JSON，透传给 parameters）'),
          TextField(
            controller: _extraCtrl,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: '{"resolution": "720P"}',
              helperText: '模型报 InvalidParameter 时，按官方示例填这里',
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50)),
            child: const Text('保存', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          title,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
      );
}
