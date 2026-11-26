import 'package:flutter_test/flutter_test.dart';
import 'package:video_app/models.dart';

void main() {
  test('拆分稿子：长句会被切成多个镜头', () {
    final shots = splitScript(
      '凌晨四点的菜市场，第一盏灯亮起。摊主推开门，热气涌出来，照亮了地上的水汽。远处的城市还在沉睡，只有这里的烟火气先醒了过来。',
    );
    expect(shots.length, greaterThanOrEqualTo(3));
    for (final s in shots) {
      expect(s.trim().isNotEmpty, true);
    }
  });

  test('拆分稿子：过短片段会合并', () {
    final shots = splitScript('天亮。市场热闹。人越来越多。');
    expect(shots.length, lessThanOrEqualTo(2));
  });

  test('提示词拼接带上风格后缀', () {
    final p = buildPrompt('深夜街道', '电影感');
    expect(p.contains('深夜街道'), true);
    expect(p.contains('电影感'), true);
  });
}
