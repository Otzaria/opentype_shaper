import 'dart:ffi';
import 'dart:io';

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

/// Resolved symbols of the native shaper.
class ShaperBindings {
  ShaperBindings._(DynamicLibrary library)
    : abiVersion = library.lookupFunction<FfiAbiVersionNative, FfiAbiVersion>(
        'opentype_shaper_abi_version',
      ),
      recordFields = library.lookupFunction<FfiAbiVersionNative, FfiAbiVersion>(
        'opentype_shaper_record_fields',
      ),
      metricFields = library.lookupFunction<FfiAbiVersionNative, FfiAbiVersion>(
        'opentype_shaper_metric_fields',
      ),
      registerFont = library
          .lookupFunction<FfiRegisterFontNative, FfiRegisterFont>(
            'opentype_shaper_register_font',
          ),
      releaseFont = library
          .lookupFunction<FfiReleaseFontNative, FfiReleaseFont>(
            'opentype_shaper_release_font',
          ),
      fontMetrics = library
          .lookupFunction<FfiFontMetricsNative, FfiFontMetrics>(
            'opentype_shaper_font_metrics',
          ),
      glyphAdvances = library
          .lookupFunction<FfiGlyphAdvancesNative, FfiGlyphAdvances>(
            'opentype_shaper_glyph_advances',
          ),
      postscriptName = library
          .lookupFunction<FfiPostscriptNameNative, FfiPostscriptName>(
            'opentype_shaper_postscript_name',
          ),
      shape = library.lookupFunction<FfiShapeNative, FfiShape>(
        'opentype_shaper_shape',
      );

  final FfiAbiVersion abiVersion;
  final FfiAbiVersion recordFields;
  final FfiAbiVersion metricFields;
  final FfiRegisterFont registerFont;
  final FfiReleaseFont releaseFont;
  final FfiFontMetrics fontMetrics;
  final FfiGlyphAdvances glyphAdvances;
  final FfiPostscriptName postscriptName;
  final FfiShape shape;

  /// The ABI this Dart code was written against.
  static const int expectedAbiVersion = 1;

  static ShaperBindings? _instance;

  /// Overrides library resolution, for tests running on the host VM where the
  /// plugin's native library is not bundled next to the executable.
  static String? libraryPathOverride;

  static ShaperBindings get instance => _instance ??= _open();

  static ShaperBindings _open() {
    final bindings = ShaperBindings._(_loadLibrary());
    final version = bindings.abiVersion();
    if (version != expectedAbiVersion) {
      throw ShaperException(
        'The native shaper reports ABI version $version, '
        'but this package expects $expectedAbiVersion.',
      );
    }
    return bindings;
  }

  static DynamicLibrary _loadLibrary() {
    final override = libraryPathOverride;
    if (override != null) {
      return DynamicLibrary.open(override);
    }
    // Apple platforms link the Rust static library into the host binary.
    if (Platform.isIOS || Platform.isMacOS) {
      return DynamicLibrary.process();
    }
    if (Platform.isWindows) {
      return DynamicLibrary.open('opentype_shaper.dll');
    }
    return DynamicLibrary.open('libopentype_shaper.so');
  }
}
