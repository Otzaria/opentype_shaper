import 'dart:ffi';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:path/path.dart' as p;

import '../../../hook/build.dart' show nativeBuild;
import '../../../hook/src/precompiled.dart';
import '../../../hook/src/rust_target.dart';

/// Builds the publisher's targets with a disposable key and checks the artifacts.
Future<void> main(List<String> targets) async {
  if (targets.isEmpty) throw ArgumentError('Pass at least one Rust target');
  final keys = ed.generateKey();
  final out = Directory.systemTemp.createTempSync('publisher_smoke_');
  try {
    final result = await Process.run(
      Platform.resolvedExecutable,
      [
        'run',
        'bin/precompiled_binaries.dart',
        'build',
        '--out',
        out.path,
        for (final target in targets) ...['--target', target],
      ],
      environment: {
        'PRIVATE_KEY': keys.privateKey.bytes
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join(),
      },
    );
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    if (result.exitCode != 0) {
      throw StateError('Publisher exited with ${result.exitCode}');
    }

    final hostArchitecture = switch (Architecture.current) {
      Architecture.arm64 => 'aarch64-',
      Architecture.x64 => 'x86_64-',
      final architecture => throw UnsupportedError('Host: $architecture'),
    };
    for (final triple in targets) {
      final target = RustTarget.fromTriple(triple);
      final asset = PrecompiledBinaries.assetName(
        target,
        target.libraryFileName(nativeBuild.cargo.libName),
      );
      final library = File(p.join(out.path, asset));
      final signature = File('${library.path}.sig').readAsBytesSync();
      if (!ed.verify(keys.publicKey, library.readAsBytesSync(), signature)) {
        throw StateError('Invalid signature for $asset');
      }
      if (target.os == OS.current && triple.startsWith(hostArchitecture)) {
        final loaded = DynamicLibrary.open(library.path);
        try {
          final abi = loaded.lookupFunction<Int32 Function(), int Function()>(
            'opentype_shaper_abi_version',
          );
          if (abi() != 1) throw StateError('Unexpected ABI in $asset');
        } finally {
          loaded.close();
        }
      }
      stdout.writeln('Verified $asset');
    }
  } finally {
    out.deleteSync(recursive: true);
  }
}
