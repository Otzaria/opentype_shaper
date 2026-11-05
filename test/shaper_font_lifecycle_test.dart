import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opentype_shaper/opentype_shaper.dart';
import 'package:opentype_shaper/src/bindings.dart';

Uint8List _fontWithoutTables({bool withHead = false}) {
  final data = ByteData(withHead ? 82 : 12)..setUint32(0, 0x10000);
  if (withHead) {
    data
      ..setUint16(4, 1)
      ..setUint16(6, 16)
      ..setUint32(12, 0x68656164)
      ..setUint32(20, 28)
      ..setUint32(24, 54)
      ..setUint32(28, 0x10000)
      ..setUint16(46, 1000);
  }
  return data.buffer.asUint8List();
}

int _registerNative(Uint8List bytes) => using((arena) {
  final data = arena<Uint8>(bytes.length);
  data.asTypedList(bytes.length).setAll(0, bytes);
  return ShaperBindings.instance.registerFont(data, bytes.length, 0);
});

void main() {
  for (final withHead in [false, true]) {
    final operation = withHead ? 'glyph advances' : 'font metrics';
    test('releases a registration when reading $operation fails', () {
      final bytes = _fontWithoutTables(withHead: withHead);
      final bindings = ShaperBindings.instance;
      final handle = _registerNative(bytes);
      expect(
        handle,
        greaterThan(0),
        reason: 'The SFNT container is parseable.',
      );
      addTearDown(() {
        while (bindings.releaseFont(handle) == ShaperStatus.ok) {}
      });

      expect(
        () => ShaperFont.register(bytes),
        throwsA(
          isA<ShaperException>()
              .having((e) => e.code, 'code', ShaperStatus.tableMissing)
              .having((e) => e.message, 'operation', contains(operation)),
        ),
      );

      expect(bindings.releaseFont(handle), ShaperStatus.ok);
      expect(bindings.releaseFont(handle), ShaperStatus.unknownHandle);
    });
  }

  final fontPath = Platform.environment['OPENTYPE_SHAPER_TEST_FONT'];
  final bytes = fontPath == null ? null : File(fontPath).readAsBytesSync();
  group('ownership', () {
    test(
      'attached wrappers free their buffers without releasing the owner',
      () {
        final owner = ShaperFont.register(bytes!);
        final attached = ShaperFont.attach(owner.handle);
        try {
          attached.shape('בדיקה', language: 'he', features: '+kern');
          attached.dispose();
          attached.dispose();
          expect(() => attached.shape('א'), throwsA(isA<ShaperException>()));
          expect(owner.shape('עדיין חי').glyphCount, greaterThan(0));
        } finally {
          attached.dispose();
          owner.dispose();
        }
      },
    );

    test('an attachment does not keep the registry reference alive', () {
      final owner = ShaperFont.register(bytes!);
      final attached = ShaperFont.attach(owner.handle);
      owner.dispose();
      try {
        expect(
          () => attached.shape('בדיקה'),
          throwsA(
            isA<ShaperException>().having(
              (e) => e.code,
              'code',
              ShaperStatus.unknownHandle,
            ),
          ),
        );
      } finally {
        attached.dispose();
      }
    });

    test('duplicate registrations release exactly one reference each', () {
      final first = ShaperFont.register(bytes!);
      final second = ShaperFont.register(bytes);
      try {
        expect(second.handle, first.handle);
        first.dispose();
        first.dispose();
        expect(second.shape('בדיקה').glyphCount, greaterThan(0));
      } finally {
        first.dispose();
        second.dispose();
      }
      expect(
        () => ShaperFont.attach(second.handle),
        throwsA(isA<ShaperException>()),
      );
    });
  }, skip: bytes == null ? 'set OPENTYPE_SHAPER_TEST_FONT' : null);
}
