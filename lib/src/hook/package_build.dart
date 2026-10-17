import 'cargo_build.dart';
import 'native_build.dart';
import 'precompiled.dart';

/// Flutter 3.38.1 writes MinimumOSVersion=12.0 into native iOS frameworks.
/// A device binary requiring a newer OS makes App Store validation reject it.
/// Keep this in the hashed configuration so changing it publishes a new set.
const precompiledIosVersion = '12.0';

/// Rust's ARM64 simulator target requires iOS 14. Simulator binaries never
/// enter a device archive, so they do not share the device framework's ceiling.
const precompiledIosArm64SimulatorVersion = '14.0';

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
