import 'dart:ffi';

import 'errors.dart';

typedef FfiAbiVersionNative = Int32 Function();
typedef FfiAbiVersion = int Function();

typedef FfiRegisterFontNative = Int64 Function(Pointer<Uint8>, Size, Uint32);
typedef FfiRegisterFont = int Function(Pointer<Uint8>, int, int);

typedef FfiReleaseFontNative = Int32 Function(Int64);
typedef FfiReleaseFont = int Function(int);

typedef FfiFontMetricsNative =
    Int32 Function(Int64, Pointer<Int32>, Size, Pointer<Uint32>);
typedef FfiFontMetrics =
    int Function(int, Pointer<Int32>, int, Pointer<Uint32>);

typedef FfiGlyphAdvancesNative =
    Int32 Function(Int64, Pointer<Uint16>, Size, Pointer<Uint32>);
typedef FfiGlyphAdvances =
    int Function(int, Pointer<Uint16>, int, Pointer<Uint32>);

typedef FfiPostscriptNameNative =
    Int32 Function(Int64, Pointer<Uint8>, Size, Pointer<Uint32>);
typedef FfiPostscriptName =
    int Function(int, Pointer<Uint8>, int, Pointer<Uint32>);

typedef FfiShapeNative =
    Int32 Function(
      Int64,
      Pointer<Uint16>,
      Size,
      Int32,
      Uint32,
      Pointer<Uint8>,
      Size,
      Pointer<Uint8>,
      Size,
      Pointer<Int32>,
      Size,
      Pointer<Uint32>,
    );
typedef FfiShape =
    int Function(
      int,
      Pointer<Uint16>,
      int,
      int,
      int,
      Pointer<Uint8>,
      int,
      Pointer<Uint8>,
      int,
      Pointer<Int32>,
      int,
      Pointer<Uint32>,
    );

@Native<FfiAbiVersionNative>(symbol: 'opentype_shaper_abi_version')
external int _abiVersion();

@Native<FfiAbiVersionNative>(symbol: 'opentype_shaper_record_fields')
external int _recordFields();

@Native<FfiAbiVersionNative>(symbol: 'opentype_shaper_metric_fields')
external int _metricFields();

@Native<FfiRegisterFontNative>(symbol: 'opentype_shaper_register_font')
external int _registerFont(Pointer<Uint8> data, int length, int faceIndex);

@Native<FfiReleaseFontNative>(symbol: 'opentype_shaper_release_font')
external int _releaseFont(int handle);

@Native<FfiFontMetricsNative>(symbol: 'opentype_shaper_font_metrics')
external int _fontMetrics(
  int handle,
  Pointer<Int32> out,
  int capacity,
  Pointer<Uint32> written,
);

@Native<FfiGlyphAdvancesNative>(symbol: 'opentype_shaper_glyph_advances')
external int _glyphAdvances(
  int handle,
  Pointer<Uint16> glyphs,
  int count,
  Pointer<Uint32> out,
);

@Native<FfiPostscriptNameNative>(symbol: 'opentype_shaper_postscript_name')
external int _postscriptName(
  int handle,
  Pointer<Uint8> out,
  int capacity,
  Pointer<Uint32> written,
);

// Leaf: the native side never calls back into Dart, so the per-call
// transition out of the Dart VM is skipped on the hot shaping path.
@Native<FfiShapeNative>(symbol: 'opentype_shaper_shape', isLeaf: true)
external int _shape(
  int handle,
  Pointer<Uint16> text,
  int textLength,
  int direction,
  int script,
  Pointer<Uint8> language,
  int languageLength,
  Pointer<Uint8> features,
  int featuresLength,
  Pointer<Int32> out,
  int capacity,
  Pointer<Uint32> written,
);

/// Resolved symbols of the native shaper.
///
/// The library is the package's code asset, bundled by the build hook.
class ShaperBindings {
  ShaperBindings._();

  final FfiAbiVersion abiVersion = _abiVersion;
  final FfiAbiVersion recordFields = _recordFields;
  final FfiAbiVersion metricFields = _metricFields;
  final FfiRegisterFont registerFont = _registerFont;
  final FfiReleaseFont releaseFont = _releaseFont;
  final FfiFontMetrics fontMetrics = _fontMetrics;
  final FfiGlyphAdvances glyphAdvances = _glyphAdvances;
  final FfiPostscriptName postscriptName = _postscriptName;
  final FfiShape shape = _shape;

  /// The ABI this Dart code was written against.
  static const int expectedAbiVersion = 1;

  static ShaperBindings? _instance;

  static ShaperBindings get instance => _instance ??= _open();

  static ShaperBindings _open() {
    final bindings = ShaperBindings._();
    final version = bindings.abiVersion();
    if (version != expectedAbiVersion) {
      throw ShaperException(
        'The native shaper reports ABI version $version, '
        'but this package expects $expectedAbiVersion.',
      );
    }
    return bindings;
  }
}
