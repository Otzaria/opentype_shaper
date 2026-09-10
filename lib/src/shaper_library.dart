import 'bindings.dart';

/// Control over how the native shaper is located and loaded.
class ShaperLibrary {
  const ShaperLibrary._();

  /// Loads the native library from an explicit path instead of the bundled
  /// plugin location.
  ///
  /// Set this before the first shaping call. Host-VM tests need it: a plugin's
  /// native library is only placed next to the executable by a Flutter build,
  /// so a `dart test` run has to point at the compiled artefact itself.
  static set path(String? value) => ShaperBindings.libraryPathOverride = value;

  static String? get path => ShaperBindings.libraryPathOverride;

  /// The ABI version the loaded library reports. Loads it if needed.
  static int get abiVersion => ShaperBindings.instance.abiVersion();

  /// Int32 fields the native side writes per shaped glyph.
  static int get recordFields => ShaperBindings.instance.recordFields();
}
