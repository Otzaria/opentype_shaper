import 'bindings.dart';

/// Information about the loaded native shaper.
class ShaperLibrary {
  const ShaperLibrary._();

  /// The ABI version the loaded library reports. Loads it if needed.
  static int get abiVersion => ShaperBindings.instance.abiVersion();

  /// Int32 fields the native side writes per shaped glyph.
  static int get recordFields => ShaperBindings.instance.recordFields();
}
