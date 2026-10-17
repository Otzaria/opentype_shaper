import 'cargo_build.dart';
import 'native_build.dart';
import 'precompiled.dart';

/// The native shaper, shared by `hook/build.dart` and `tool/precompiled_binaries`.
const nativeBuild = NativeBuild(
  assetName: 'src/bindings.dart',
  cargo: CargoOptions(libName: 'opentype_shaper'),
  precompiled: PrecompiledBinaries(
    urlPrefix:
        'https://github.com/Otzaria/opentype_shaper/releases/download/precompiled_',
    publicKeyHex:
        'afe7c2822d2b006eedee1d730b08216e36cd59defbc188f30579e61823644273',
  ),
);
