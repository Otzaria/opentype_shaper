#
# Run `pod lib lint opentype_shaper.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'opentype_shaper'
  s.version          = '0.1.0'
  s.summary          = 'OpenType text shaping for Dart and Flutter.'
  s.description      = <<-DESC
GSUB substitutions and GPOS mark positioning, returning glyph ids with
per-glyph offsets.
                       DESC
  s.homepage         = 'https://github.com/Otzaria/opentype_shaper'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Otzaria' => 'otzaria.getit@gmail.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.swift_version    = '5.0'

  s.script_phase = {
    :name => 'Build Rust library',
    :script => 'sh "$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh" ../rust opentype_shaper',
    :execution_position => :before_compile,
    :input_files => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
    :output_files => ["${BUILT_PRODUCTS_DIR}/libopentype_shaper.a"],
  }
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'OTHER_LDFLAGS' => '-force_load ${BUILT_PRODUCTS_DIR}/libopentype_shaper.a',
  }
end
