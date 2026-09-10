/// Thrown when the native shaper cannot satisfy a request.
class ShaperException implements Exception {
  const ShaperException(this.message, {this.code});

  final String message;

  /// The native status code, when the failure came from across the ABI.
  final int? code;

  @override
  String toString() => code == null
      ? 'ShaperException: $message'
      : 'ShaperException: $message ($code)';
}

/// Status codes mirrored from `rust/src/lib.rs`.
class ShaperStatus {
  const ShaperStatus._();

  static const int ok = 0;
  static const int invalidArgument = -1;
  static const int fontParse = -2;
  static const int unknownHandle = -3;
  static const int panic = -4;
  static const int tableMissing = -5;
  static const int bufferTooSmall = -10;

  static String describe(int code) => switch (code) {
    ok => 'ok',
    invalidArgument => 'invalid argument',
    fontParse => 'the font could not be parsed',
    unknownHandle => 'unknown font handle',
    panic => 'the shaper panicked',
    tableMissing => 'a required font table is missing',
    bufferTooSmall => 'the output buffer was too small',
    _ => 'unknown error $code',
  };
}
