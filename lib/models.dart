enum ShotStatus { idle, running, done, failed }

class Shot {
  Shot({required this.prompt});

  String prompt;
  ShotStatus status = ShotStatus.idle;
  String? videoPath;
  String? error;
  int elapsedMs = 0;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'prompt': prompt,
        'status': status.name,
        'videoPath': videoPath,
        'error': error,
        'elapsedMs': elapsedMs,
      };

  static Shot fromJson(Map<String, dynamic> j) {
    final shot = Shot(prompt: (j['prompt'] as String?) ?? '');
    shot.status = ShotStatus.values.firstWhere(
      (s) => s.name == j['status'],
      orElse: () => ShotStatus.idle,
    );
    shot.videoPath = j['videoPath'] as String?;
    shot.error = j['error'] as String?;
    shot.elapsedMs = (j['elapsedMs'] as num?)?.toInt() ?? 0;
    return shot;
  }
}

class Job {
  Job({
    required this.id,
    required this.script,
    required this.shots,
    required this.createdAt,
  });

  final String id;
  final String script;
  final List<Shot> shots;
  final DateTime createdAt;

  int get doneCount => shots.where((s) => s.status == ShotStatus.done).length;
  int get failedCount => shots.where((s) => s.status == ShotStatus.failed).length;

  String get title {
    final one = script.replaceAll('\n', ' ').trim();
    if (one.isEmpty) return '未命名稿件';
    return one.length > 16 ? '${one.substring(0, 16)}…' : one;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'script': script,
        'createdAt': createdAt.toIso8601String(),
        'shots': shots.map((s) => s.toJson()).toList(),
      };

  static Job fromJson(Map<String, dynamic> j) => Job(
        id: (j['id'] as String?) ?? '',
        script: (j['script'] as String?) ?? '',
        createdAt: DateTime.tryParse((j['createdAt'] as String?) ?? '') ?? DateTime.now(),
        shots: ((j['shots'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Shot.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

/// 把稿子切成镜头文案
/// 短视频场景：一句一镜，默认每镜 10~26 字
List<String> splitScript(String text, {int minLen = 10, int maxLen = 26}) {
  final cleaned = text.replaceAll('\r', '');
  final pieces = cleaned
      .split(RegExp(r'[。！？!?；;\n]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  final chunks = <String>[];
  var buf = '';
  for (final p in pieces) {
    if (buf.isEmpty) {
      buf = p;
    } else if (buf.length + p.length + 1 <= maxLen) {
      buf = '$buf，$p';
    } else {
      chunks.add(buf);
      buf = p;
    }
    if (buf.length >= maxLen) {
      chunks.add(buf);
      buf = '';
    }
  }
  if (buf.trim().isNotEmpty) chunks.add(buf.trim());

  final merged = <String>[];
  for (final s in chunks) {
    if (merged.isNotEmpty &&
        merged.last.length < minLen &&
        merged.last.length + s.length + 1 <= maxLen) {
      merged[merged.length - 1] = '${merged.last}，$s';
    } else {
      merged.add(s);
    }
  }
  return merged;
}

String buildPrompt(String text, String style) {
  final t = text.trim();
  final s = style.trim();
  if (t.isEmpty) return s;
  if (s.isEmpty) return t;
  return '$t。$s';
}
