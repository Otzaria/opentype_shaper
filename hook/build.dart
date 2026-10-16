import 'package:hooks/hooks.dart';

import 'src/cargo_build.dart';
import 'src/native_build.dart';
import 'src/precompiled.dart';

/// The native shaper, shared by the build hook and `tool/precompiled_binaries.dart`.
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

void main(List<String> args) async {
  await build(args, nativeBuild.run);
}
