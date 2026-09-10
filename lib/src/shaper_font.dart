import 'dart:collection';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'bindings.dart';
import 'errors.dart';
import 'font_metrics.dart';
import 'shaped_run.dart';

/// A font registered with the native shaper, ready to shape runs of text.
///
/// Registering parses the font's shaping tables once, which is the expensive
/// step; shaping a word then costs a few microseconds. Identical bytes share
/// one native entry, so registering the same font twice is cheap.
///
/// A font is not tied to a size: results come back in font units, so one shaped
/// run serves every point size.
class ShaperFont {
  ShaperFont._(
    this._handle,
    this.metrics,
    this.glyphAdvances,
    this.postScriptName, {
    required bool ownsHandle,
  }) : _ownsHandle = ownsHandle;

  /// Registers `bytes` and reads the font's metrics.
  ///
  /// `faceIndex` selects a face inside a font collection (`.ttc`/`.otc`).
  factory ShaperFont.register(Uint8List bytes, {int faceIndex = 0}) {
    if (bytes.isEmpty) {
      throw const ShaperException('The font data is empty.');
    }
    final bindings = ShaperBindings.instance;
    final native = calloc<Uint8>(bytes.length);
    try {
      native.asTypedList(bytes.length).setAll(0, bytes);
      final handle = bindings.registerFont(native, bytes.length, faceIndex);
      if (handle <= 0) {
        throw ShaperException(
          'The font could not be registered: ${ShaperStatus.describe(handle)}.',
          code: handle,
        );
      }
      return ShaperFont._attach(handle, ownsHandle: true);
    } finally {
      calloc.free(native);
    }
  }

  /// Attaches to a font already registered in this process.
  ///
  /// Handles are plain integers and the native registry is process-wide, so a
  /// background isolate can shape with a font the main isolate registered by
  /// passing the handle across rather than the bytes.
  ///
  /// An attached font does not own the registry reference: disposing it frees
  /// only its own buffers, and the isolate that registered the font releases it.
  factory ShaperFont.attach(int handle) =>
      ShaperFont._attach(handle, ownsHandle: false);

  factory ShaperFont._attach(int handle, {required bool ownsHandle}) {
    final bindings = ShaperBindings.instance;
    final fieldCount = bindings.metricFields();

    final metricBuffer = calloc<Int32>(fieldCount);
    final countBuffer = calloc<Uint32>();
    try {
      var status = bindings.fontMetrics(
        handle,
        metricBuffer,
        fieldCount,
        countBuffer,
      );
      _check(status, 'read the font metrics');
      final metrics = FontMetrics.fromNative(
        Int32List.fromList(metricBuffer.asTypedList(fieldCount)),
      );

      final advances = calloc<Uint16>(metrics.glyphCount);
      try {
        status = bindings.glyphAdvances(
          handle,
          advances,
          metrics.glyphCount,
          countBuffer,
        );
        _check(status, 'read the glyph advances');
        final glyphAdvances = Uint16List.fromList(
          advances.asTypedList(countBuffer.value),
        );

        return ShaperFont._(
          handle,
          metrics,
          glyphAdvances,
          _readPostScriptName(bindings, handle, countBuffer),
          ownsHandle: ownsHandle,
        );
      } finally {
        calloc.free(advances);
      }
    } finally {
      calloc.free(metricBuffer);
      calloc.free(countBuffer);
    }
  }

  static String _readPostScriptName(
    ShaperBindings bindings,
    int handle,
    Pointer<Uint32> countBuffer,
  ) {
    var capacity = 128;
    for (var attempt = 0; attempt < 2; attempt++) {
      final buffer = calloc<Uint8>(capacity);
      try {
        final status = bindings.postscriptName(
          handle,
          buffer,
          capacity,
          countBuffer,
        );
        if (status == ShaperStatus.ok) {
          return utf8.decode(
            buffer.asTypedList(countBuffer.value),
            allowMalformed: true,
          );
        }
        if (status == ShaperStatus.bufferTooSmall) {
          capacity = countBuffer.value;
          continue;
        }
        // A missing name table is not worth failing a load over; the PDF
        // writer falls back to a synthesised base font name.
        return '';
      } finally {
        calloc.free(buffer);
      }
    }
    return '';
  }

  final int _handle;
  final bool _ownsHandle;

  /// Metrics of the registered font, in font units.
  final FontMetrics metrics;

  /// Advance width per glyph id, in font units. A PDF `/W` array reads this.
  final Uint16List glyphAdvances;

  /// The font's PostScript name, or empty when it declares none.
  final String postScriptName;

  /// The native registry handle. Pass this to [ShaperFont.attach] in another
  /// isolate rather than re-registering the bytes.
  int get handle => _handle;

  /// How many shaped runs to remember. Hebrew text repeats words heavily, so
  /// the cache turns most shaping calls into a map lookup.
  int cacheCapacity = 8192;

  final LinkedHashMap<_ShapeKey, ShapedRun> _cache = LinkedHashMap();

  Pointer<Uint16>? _textBuffer;
  int _textCapacity = 0;
  Pointer<Int32>? _outBuffer;
  int _outCapacityRecords = 0;
  Pointer<Uint32>? _countBuffer;
  bool _disposed = false;

  /// Shapes one run of text.
  ///
  /// `script` is an ISO 15924 tag such as `hebr`; leaving it empty lets the
  /// shaper guess from the characters. `features` is a comma-separated
  /// OpenType feature list such as `-liga,+dlig`.
  ///
  /// Pass runs that are uniform in direction and font. A word is the natural
  /// unit for Hebrew, which has no shaping across spaces.
  ShapedRun shape(
    String text, {
    bool rtl = false,
    String script = '',
    String? language,
    String? features,
  }) {
    if (_disposed) {
      throw const ShaperException('This font has been disposed.');
    }
    if (text.isEmpty) {
      return ShapedRun.empty;
    }

    final key = _ShapeKey(text, rtl, script, language, features);
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }

    final run = _shapeUncached(text, rtl, script, language, features);

    if (cacheCapacity > 0) {
      _cache[key] = run;
      while (_cache.length > cacheCapacity) {
        _cache.remove(_cache.keys.first);
      }
    }
    return run;
  }

  ShapedRun _shapeUncached(
    String text,
    bool rtl,
    String script,
    String? language,
    String? features,
  ) {
    final bindings = ShaperBindings.instance;
    final units = text.codeUnits;
    final textBuffer = _ensureTextCapacity(units.length);
    textBuffer.asTypedList(units.length).setAll(0, units);

    final languageBytes = language == null ? null : utf8.encode(language);
    final featureBytes = features == null ? null : utf8.encode(features);
    final languagePointer = _allocateBytes(languageBytes);
    final featurePointer = _allocateBytes(featureBytes);

    final countBuffer = _countBuffer ??= calloc<Uint32>();
    final fieldsPerGlyph = bindings.recordFields();

    try {
      // One glyph per code unit covers text without marks; a nikud word needs
      // more, and the ABI answers with the required count instead of
      // truncating, so the buffer grows once and is reused after that.
      var capacity = units.length < 16 ? 32 : units.length * 2;
      for (var attempt = 0; attempt < 2; attempt++) {
        final outBuffer = _ensureOutCapacity(capacity, fieldsPerGlyph);
        final status = bindings.shape(
          _handle,
          textBuffer,
          units.length,
          rtl ? 1 : 0,
          _scriptTag(script),
          languagePointer ?? nullptr,
          languageBytes?.length ?? 0,
          featurePointer ?? nullptr,
          featureBytes?.length ?? 0,
          outBuffer,
          _outCapacityRecords,
          countBuffer,
        );

        if (status == ShaperStatus.ok) {
          final glyphCount = countBuffer.value;
          return ShapedRun(
            text: text,
            glyphCount: glyphCount,
            records: Int32List.fromList(
              outBuffer.asTypedList(glyphCount * fieldsPerGlyph),
            ),
            fieldsPerGlyph: fieldsPerGlyph,
            unitsPerEm: metrics.unitsPerEm,
          );
        }
        if (status == ShaperStatus.bufferTooSmall) {
          capacity = countBuffer.value;
          continue;
        }
        _check(status, 'shape the text');
      }
      throw const ShaperException(
        'The shaper kept asking for more room than it then used.',
      );
    } finally {
      if (languagePointer != null) calloc.free(languagePointer);
      if (featurePointer != null) calloc.free(featurePointer);
    }
  }

  Pointer<Uint8>? _allocateBytes(List<int>? bytes) {
    if (bytes == null || bytes.isEmpty) {
      return null;
    }
    final pointer = calloc<Uint8>(bytes.length);
    pointer.asTypedList(bytes.length).setAll(0, bytes);
    return pointer;
  }

  Pointer<Uint16> _ensureTextCapacity(int units) {
    if (_textCapacity >= units && _textBuffer != null) {
      return _textBuffer!;
    }
    final existing = _textBuffer;
    if (existing != null) {
      calloc.free(existing);
    }
    _textCapacity = units < 64 ? 64 : units * 2;
    return _textBuffer = calloc<Uint16>(_textCapacity);
  }

  Pointer<Int32> _ensureOutCapacity(int records, int fieldsPerGlyph) {
    if (_outCapacityRecords >= records && _outBuffer != null) {
      return _outBuffer!;
    }
    final existing = _outBuffer;
    if (existing != null) {
      calloc.free(existing);
    }
    _outCapacityRecords = records < 64 ? 64 : records * 2;
    return _outBuffer = calloc<Int32>(_outCapacityRecords * fieldsPerGlyph);
  }

  static int _scriptTag(String script) {
    if (script.length != 4) {
      return 0;
    }
    var tag = 0;
    for (var index = 0; index < 4; index++) {
      tag = (tag << 8) | (script.codeUnitAt(index) & 0xFF);
    }
    return tag;
  }

  static void _check(int status, String action) {
    if (status != ShaperStatus.ok) {
      throw ShaperException(
        'Could not $action: ${ShaperStatus.describe(status)}.',
        code: status,
      );
    }
  }

  /// Releases the native reference and the scratch buffers.
  ///
  /// Attaching to the same handle elsewhere keeps the entry alive; the parsed
  /// font is freed once the last reference goes.
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _cache.clear();
    final text = _textBuffer;
    if (text != null) calloc.free(text);
    final out = _outBuffer;
    if (out != null) calloc.free(out);
    final count = _countBuffer;
    if (count != null) calloc.free(count);
    _textBuffer = null;
    _outBuffer = null;
    _countBuffer = null;
    _textCapacity = 0;
    _outCapacityRecords = 0;
    if (_ownsHandle) {
      ShaperBindings.instance.releaseFont(_handle);
    }
  }

  @override
  String toString() =>
      'ShaperFont(${postScriptName.isEmpty ? 'unnamed' : postScriptName}, '
      'handle $_handle)';
}

class _ShapeKey {
  const _ShapeKey(
    this.text,
    this.rtl,
    this.script,
    this.language,
    this.features,
  );

  final String text;
  final bool rtl;
  final String script;
  final String? language;
  final String? features;

  @override
  bool operator ==(Object other) =>
      other is _ShapeKey &&
      other.rtl == rtl &&
      other.text == text &&
      other.script == script &&
      other.language == language &&
      other.features == features;

  @override
  int get hashCode => Object.hash(text, rtl, script, language, features);
}
