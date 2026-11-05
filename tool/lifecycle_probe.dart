import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:opentype_shaper/opentype_shaper.dart';

// glibc reports allocator-owned bytes, independently of the Dart heap and GC.
final class _MallInfo2 extends Struct {
  @Size()
  external int arena;
  @Size()
  external int ordblks;
  @Size()
  external int smblks;
  @Size()
  external int hblks;
  @Size()
  external int hblkhd;
  @Size()
  external int usmblks;
  @Size()
  external int fsmblks;
  @Size()
  external int uordblks;
  @Size()
  external int fordblks;
  @Size()
  external int keepcost;
}

Future<int> _worker(int handle, {required bool dispose}) => Isolate.run(() {
  final font = ShaperFont.attach(handle);
  try {
    final run = font.shape(
      'abc 123 ' * 1024,
      script: 'latn',
      language: 'en',
      features: 'kern=1',
    );
    return run.records.fold<int>(0, (sum, field) => sum + field);
  } finally {
    if (dispose) font.dispose();
  }
});

Future<void> main(List<String> arguments) async {
  if (!Platform.isLinux || arguments.isEmpty) {
    stderr.writeln(
      'Usage (Linux/glibc): dart run tool/lifecycle_probe.dart FONT_PATH '
      '[--retain-buffers]',
    );
    exitCode = 64;
    return;
  }
  final library = DynamicLibrary.open('libc.so.6');
  final mallinfo = library
      .lookupFunction<_MallInfo2 Function(), _MallInfo2 Function()>(
        'mallinfo2',
      );
  final trim = library.lookupFunction<Int32 Function(Size), int Function(int)>(
    'malloc_trim',
  );
  ({int allocated, int rss}) sample() {
    trim(0);
    final info = mallinfo();
    return (
      allocated: info.uordblks + info.hblkhd,
      rss: ProcessInfo.currentRss,
    );
  }

  final dispose = !arguments.contains('--retain-buffers');
  final owner = ShaperFont.register(File(arguments.first).readAsBytesSync());
  try {
    final expected = await _worker(owner.handle, dispose: true);
    for (var warmup = 0; warmup < 4; warmup++) {
      await _worker(owner.handle, dispose: true);
    }
    final before = sample();
    final stopwatch = Stopwatch()..start();
    const cycles = 30;
    for (var cycle = 0; cycle < cycles; cycle++) {
      final result = await _worker(owner.handle, dispose: dispose);
      if (result != expected) throw StateError('Shaping output changed.');
    }
    stopwatch.stop();
    final after = sample();
    stdout.writeln(
      jsonEncode({
        'disposeAttachments': dispose,
        'cycles': cycles,
        'nativeAllocatedBefore': before.allocated,
        'nativeAllocatedAfter': after.allocated,
        'nativeAllocatedDelta': after.allocated - before.allocated,
        'rssBefore': before.rss,
        'rssAfter': after.rss,
        'rssDelta': after.rss - before.rss,
        'elapsedMicroseconds': stopwatch.elapsedMicroseconds,
        'shapeChecksum': expected,
      }),
    );
  } finally {
    owner.dispose();
  }
}
