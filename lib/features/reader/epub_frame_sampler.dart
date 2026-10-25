/// Bounded, in-memory frame duration samples for an explicitly requested
/// reader profiling window. No book content, resource names or identifiers
/// are recorded. A fixed-size ring protects memory on high-refresh devices.
class EpubFrameProfile {
  const EpubFrameProfile({
    required this.reportedFrames,
    required this.sampledFrames,
    required this.p95BuildUs,
    required this.p95RasterUs,
    required this.p95TotalUs,
    required this.maxBuildUs,
    required this.maxRasterUs,
    required this.overBudgetBuildFrames,
    required this.overBudgetRasterFrames,
  });

  /// Includes all valid frames even if the ring discarded older samples.
  final int reportedFrames;
  final int sampledFrames;
  final int p95BuildUs;
  final int p95RasterUs;
  final int p95TotalUs;
  final int maxBuildUs;
  final int maxRasterUs;
  /// Strictly over 16.7ms, a reference for 60Hz (not device-aware jank).
  final int overBudgetBuildFrames;
  final int overBudgetRasterFrames;
}

class EpubFrameSampler {
  EpubFrameSampler({this.maxFrames = 4096}) {
    if (maxFrames < 1 || maxFrames > 4096) {
      throw ArgumentError.value(maxFrames, 'maxFrames');
    }
    _build = List<int>.filled(maxFrames, 0);
    _raster = List<int>.filled(maxFrames, 0);
    _total = List<int>.filled(maxFrames, 0);
  }

  final int maxFrames;
  late final List<int> _build;
  late final List<int> _raster;
  late final List<int> _total;
  int _count = 0;

  void record({
    required int buildUs,
    required int rasterUs,
    required int totalUs,
  }) {
    if (buildUs < 0 || rasterUs < 0 || totalUs < 0) return;
    final index = _count % maxFrames;
    _build[index] = buildUs;
    _raster[index] = rasterUs;
    _total[index] = totalUs;
    _count++;
  }

  EpubFrameProfile snapshot() {
    final sampleCount = _count < maxFrames ? _count : maxFrames;
    final build = _build.sublist(0, sampleCount)..sort();
    final raster = _raster.sublist(0, sampleCount)..sort();
    final total = _total.sublist(0, sampleCount)..sort();
    // Nearest-rank p95 on the *retained* fixed-size sample. A zero-frame
    // window reports zero, never a made-up time or inferred refresh rate.
    int p95(List<int> sorted) {
      if (sorted.isEmpty) return 0;
      final rank = ((sorted.length * 95 + 99) ~/ 100) - 1;
      return sorted[rank];
    }
    const budget60HzUs = 16700;
    return EpubFrameProfile(
      reportedFrames: _count,
      sampledFrames: sampleCount,
      p95BuildUs: p95(build),
      p95RasterUs: p95(raster),
      p95TotalUs: p95(total),
      maxBuildUs: build.isEmpty ? 0 : build.last,
      maxRasterUs: raster.isEmpty ? 0 : raster.last,
      overBudgetBuildFrames:
          build.where((value) => value > budget60HzUs).length,
      overBudgetRasterFrames:
          raster.where((value) => value > budget60HzUs).length,
    );
  }
}
