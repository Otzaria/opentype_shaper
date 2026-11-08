import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opentype_shaper/opentype_shaper.dart';
import 'package:opentype_shaper/src/bindings.dart';

Uint8List _removeTable(Uint8List font, String table) {
  final bytes = Uint8List.fromList(font);
  final view = ByteData.sublistView(bytes);
  for (var index = 0; index < view.getUint16(4); index++) {
    final offset = 12 + index * 16;
    if (String.fromCharCodes(bytes.sublist(offset, offset + 4)) == table) {
      view.setUint32(offset + 8, bytes.length);
      view.setUint32(offset + 12, 0);
      return bytes;
    }
  }
  throw StateError('The test font must contain $table.');
}

int _registerNative(Uint8List bytes) => using((arena) {
  final pointer = arena<Uint8>(bytes.length);
  pointer.asTypedList(bytes.length).setAll(0, bytes);
  return ShaperBindings.instance.registerFont(pointer, bytes.length, 0);
});

int _status(int handle) => using((arena) {
  final bindings = ShaperBindings.instance;
  final fields = bindings.metricFields();
  return bindings.fontMetrics(
    handle,
    arena<Int32>(fields),
    fields,
    arena<Uint32>(),
  );
});

void main() {
  final path = Platform.environment['OPENTYPE_SHAPER_TEST_FONT'];
  final bytes = path == null ? null : File(path).readAsBytesSync();

  group('native resource ownership', () {
    for (final table in ['head', 'maxp']) {
      test('failed $table loading releases only the acquired reference', () {
        final malformed = _removeTable(bytes!, table);
        for (var cycle = 0; cycle < 30; cycle++) {
          final handle = _registerNative(malformed);
          expect(handle, greaterThan(0));
          try {
            expect(
              () => ShaperFont.register(malformed),
              throwsA(isA<ShaperException>()),
            );
            expect(
              () => ShaperFont.attach(handle),
              throwsA(isA<ShaperException>()),
            );
            expect(
              ShaperBindings.instance.releaseFont(handle),
              ShaperStatus.ok,
              reason: 'failed attachment must not release the caller\'s owner',
            );
            expect(
              _status(handle),
              ShaperStatus.unknownHandle,
              reason: 'failed construction must not retain a native reference',
            );
          } finally {
            while (ShaperBindings.instance.releaseFont(handle) ==
                ShaperStatus.ok) {}
          }
        }
      });
    }

    test('30 register/attach/dispose cycles preserve output and refcounts', () {
      List<int>? expected;
      for (var cycle = 0; cycle < 30; cycle++) {
        final owner = ShaperFont.register(bytes!);
        final anotherOwner = ShaperFont.register(bytes);
        final handle = owner.handle;
        expect(anotherOwner.handle, handle);
        try {
          final attached = ShaperFont.attach(handle);
          try {
            final result = attached.shape(
              'אבג 123',
              rtl: true,
              script: 'hebr',
              language: 'he',
              features: 'kern=1',
            );
            expected ??= result.records.toList();
            expect(result.records, orderedEquals(expected));
            attached.shape('אבג 123' * 200, rtl: true);
          } finally {
            attached.dispose();
            attached.dispose();
          }
          expect(_status(handle), ShaperStatus.ok);
          owner.dispose();
          expect(_status(handle), ShaperStatus.ok);
          expect(anotherOwner.shape('123').isNotEmpty, isTrue);
        } finally {
          anotherOwner.dispose();
          owner.dispose();
        }
        expect(_status(handle), ShaperStatus.unknownHandle);
      }
    });

    test('attachments do not keep an owner alive', () {
      final owner = ShaperFont.register(bytes!);
      final handle = owner.handle;
      final attached = ShaperFont.attach(handle);
      try {
        owner.dispose();
        expect(
          () => attached.shape('123', language: 'en', features: 'kern=1'),
          throwsA(
            isA<ShaperException>().having(
              (error) => error.code,
              'code',
              ShaperStatus.unknownHandle,
            ),
          ),
        );
      } finally {
        attached.dispose();
        owner.dispose();
      }
      expect(_status(handle), ShaperStatus.unknownHandle);
    });

    test(
      '30 failed workers leave ownership with the awaiting caller',
      () async {
        for (var cycle = 0; cycle < 30; cycle++) {
          final owner = ShaperFont.register(bytes!);
          final handle = owner.handle;
          try {
            await expectLater(
              Isolate.run(() {
                final attached = ShaperFont.attach(handle);
                try {
                  attached.shape('123', language: 'en');
                  throw StateError('worker failed');
                } finally {
                  attached.dispose();
                }
              }),
              throwsStateError,
            );
            expect(_status(handle), ShaperStatus.ok);
          } finally {
            owner.dispose();
          }
          expect(_status(handle), ShaperStatus.unknownHandle);
        }
      },
    );
  }, skip: bytes == null ? 'set OPENTYPE_SHAPER_TEST_FONT' : null);
}
