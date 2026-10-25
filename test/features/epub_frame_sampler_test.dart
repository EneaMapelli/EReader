import 'package:ereader/features/reader/epub_frame_sampler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty capture has no invented frame timings', () {
    final stats = EpubFrameSampler().snapshot();
    expect(stats.reportedFrames, 0);
    expect(stats.sampledFrames, 0);
    expect(stats.p95BuildUs, 0);
    expect(stats.p95RasterUs, 0);
    expect(stats.maxBuildUs, 0);
  });

  test('nearest-rank percentiles and 60Hz reference counters are exact', () {
    final collector = EpubFrameSampler(maxFrames: 32);
    for (var i = 1; i <= 20; i++) {
      collector.record(
        buildUs: i * 1000,
        rasterUs: (21 - i) * 1000,
        totalUs: i * 2000,
      );
    }
    final stats = collector.snapshot();
    expect(stats.reportedFrames, 20);
    expect(stats.sampledFrames, 20);
    expect(stats.p95BuildUs, 19000);
    expect(stats.p95RasterUs, 19000);
    expect(stats.p95TotalUs, 38000);
    expect(stats.maxBuildUs, 20000);
    expect(stats.maxRasterUs, 20000);
    expect(stats.overBudgetBuildFrames, 4);
    expect(stats.overBudgetRasterFrames, 4);
  });

  test('fixed ring contains only the most recent bounded sample', () {
    final collector = EpubFrameSampler(maxFrames: 3);
    for (final value in [1000, 2000, 3000, 9000, 11000]) {
      collector.record(
        buildUs: value, rasterUs: value, totalUs: value * 2,
      );
    }
    final stats = collector.snapshot();
    expect(stats.reportedFrames, 5);
    expect(stats.sampledFrames, 3);
    expect(stats.maxBuildUs, 11000);
    expect(stats.p95BuildUs, 11000);
    expect(stats.overBudgetBuildFrames, 0);
  });

  test('invalid durations are ignored without allocating more samples', () {
    final collector = EpubFrameSampler(maxFrames: 2);
    collector.record(buildUs: -1, rasterUs: 4, totalUs: 6);
    collector.record(buildUs: 4, rasterUs: -1, totalUs: 6);
    collector.record(buildUs: 4, rasterUs: 6, totalUs: -1);
    expect(collector.snapshot().reportedFrames, 0);
    expect(() => EpubFrameSampler(maxFrames: 0), throwsArgumentError);
    expect(() => EpubFrameSampler(maxFrames: 4097), throwsArgumentError);
  });
}
