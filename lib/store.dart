import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class AppSettings {
  AppSettings({
    this.baseUrl = 'https://dashscope.aliyuncs.com/api/v1',
    this.model = 'wan3.0-video',
    this.size = '720*1280',
    this.duration = 5,
    this.styleSuffix = '35mm胶片质感，浅景深，电影感调色，光影层次丰富，缓慢推镜',
    this.maxShots = 4,
    this.extraParamsJson = '',
  });

  String baseUrl;
  String model;
  String size;
  int duration;
  String styleSuffix;
  int maxShots;
  String extraParamsJson;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'baseUrl': baseUrl,
        'model': model,
        'size': size,
        'duration': duration,
        'styleSuffix': styleSuffix,
        'maxShots': maxShots,
        'extraParamsJson': extraParamsJson,
      };

  static AppSettings fromJson(Map<String, dynamic> j) => AppSettings(
        baseUrl: (j['baseUrl'] as String?) ??
            'https://dashscope.aliyuncs.com/api/v1',
        model: (j['model'] as String?) ?? 'wan3.0-video',
        size: (j['size'] as String?) ?? '720*1280',
        duration: (j['duration'] as num?)?.toInt() ?? 5,
        styleSuffix: (j['styleSuffix'] as String?) ??
            '35mm胶片质感，浅景深，电影感调色，光影层次丰富，缓慢推镜',
        maxShots: (j['maxShots'] as num?)?.toInt() ?? 4,
        extraParamsJson: (j['extraParamsJson'] as String?) ?? '',
      );

  /// 高级参数（原样透传给 parameters）
  Map<String, dynamic> get extraParams {
    final raw = extraParamsJson.trim();
    if (raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // ignore
    }
    return <String, dynamic>{};
  }
}

class AppStore extends ChangeNotifier {
  AppStore._();

  static final AppStore instance = AppStore._();

  static const String _keyPrefs = 'settings_v1';
  static const String _jobsPrefs = 'jobs_v1';
  static const String _secureKeyName = 'dashscope_api_key';

  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  AppSettings settings = AppSettings();
  List<Job> jobs = <Job>[];
  String apiKey = '';
  bool loaded = false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawSettings = prefs.getString(_keyPrefs);
    if (rawSettings != null && rawSettings.isNotEmpty) {
      try {
        settings = AppSettings.fromJson(
            Map<String, dynamic>.from(jsonDecode(rawSettings) as Map));
      } catch (_) {
        settings = AppSettings();
      }
    }
    final rawJobs = prefs.getString(_jobsPrefs);
    if (rawJobs != null && rawJobs.isNotEmpty) {
      try {
        final list = jsonDecode(rawJobs) as List;
        jobs = list
            .whereType<Map>()
            .map((e) => Job.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {
        jobs = <Job>[];
      }
    }
    jobs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    // 上次被杀掉/闪退时可能残留「生成中」，启动时复位，避免卡在假进度
    for (final j in jobs) {
      for (final s in j.shots) {
        if (s.status == ShotStatus.running) s.status = ShotStatus.idle;
      }
    }
    try {
      apiKey = await _secure.read(key: _secureKeyName) ?? '';
    } catch (_) {
      apiKey = '';
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPrefs, jsonEncode(settings.toJson()));
    notifyListeners();
  }

  Future<void> saveApiKey(String value) async {
    apiKey = value.trim();
    try {
      if (apiKey.isEmpty) {
        await _secure.delete(key: _secureKeyName);
      } else {
        await _secure.write(key: _secureKeyName, value: apiKey);
      }
    } catch (_) {
      // 某些机型 Keystore 异常时，至少保留内存值
    }
    notifyListeners();
  }

  Future<void> _persistJobs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _jobsPrefs, jsonEncode(jobs.map((j) => j.toJson()).toList()));
    notifyListeners();
  }

  Future<void> addJob(Job job) async {
    jobs.insert(0, job);
    await _persistJobs();
  }

  Future<void> updateJob(Job job) async {
    final idx = jobs.indexWhere((j) => j.id == job.id);
    if (idx >= 0) {
      jobs[idx] = job;
    } else {
      jobs.insert(0, job);
    }
    await _persistJobs();
  }

  Future<void> deleteJob(String id) async {
    jobs.removeWhere((j) => j.id == id);
    await _persistJobs();
  }
}
