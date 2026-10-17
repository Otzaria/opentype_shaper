import 'package:hooks/hooks.dart';
// pub.dev accepts no other Dart file under hook/, so the build lives in lib/.
import 'package:opentype_shaper/src/hook/package_build.dart';

void main(List<String> args) async {
  await build(args, nativeBuild.run);
}
