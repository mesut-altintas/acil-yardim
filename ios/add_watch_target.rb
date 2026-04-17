#!/usr/bin/env ruby
# Watch App target'ı Xcode projesine programatik olarak ekler.
# GitHub Actions macOS runner'ında çalışır.
# İdempotent: target zaten varsa hiçbir şey yapmaz.
#
# NOT: PBXCopyFilesBuildPhase yerine PBXShellScriptBuildPhase kullanılır.
# Bunun nedeni: Flutter'ın "Thin Binary" scriptiyle döngü (cycle) oluşmaması için
# input/output path tanımlamak gerekir — bunu sadece shell script fazı destekler.

require 'xcodeproj'

PROJECT_PATH      = 'ios/Runner.xcodeproj'
WATCH_TARGET_NAME = 'AcilYardim Watch App'
WATCH_BUNDLE_ID   = 'com.example.acilYardim.watchapp'
WATCH_FILES_DIR   = 'AcilYardim Watch App'

project = Xcodeproj::Project.open(PROJECT_PATH)

# İdempotent kontrol
if project.targets.any? { |t| t.name == WATCH_TARGET_NAME }
  puts "[watch_setup] Target '#{WATCH_TARGET_NAME}' zaten mevcut, atlanıyor."
  exit 0
end

puts "[watch_setup] Watch target ekleniyor..."

# ── Watch App target oluştur ──
watch_target = project.new_target(
  :watch2_app,
  WATCH_TARGET_NAME,
  :watchos,
  '7.0'
)

# ── Build ayarları ──
watch_target.build_configurations.each do |config|
  config.build_settings.merge!(
    'PRODUCT_NAME'                          => WATCH_TARGET_NAME,
    'PRODUCT_BUNDLE_IDENTIFIER'             => WATCH_BUNDLE_ID,
    'SWIFT_VERSION'                         => '5.0',
    'WATCHOS_DEPLOYMENT_TARGET'             => '7.0',
    'TARGETED_DEVICE_FAMILY'                => '4',
    'SDKROOT'                               => 'watchos',
    'SUPPORTED_PLATFORMS'                   => 'watchos watchsimulator',
    'INFOPLIST_FILE'                        => "#{WATCH_FILES_DIR}/Info.plist",
    'SKIP_INSTALL'                          => 'YES',
    'ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES' => 'NO',
    'CODE_SIGN_STYLE'                       => 'Automatic',
    'DEVELOPMENT_TEAM'                      => '$(DEVELOPMENT_TEAM)',
    'LD_RUNPATH_SEARCH_PATHS'               => '$(inherited) @executable_path/Frameworks',
    'SWIFT_OPTIMIZATION_LEVEL'              => config.name == 'Debug' ? '-Onone' : '-O',
  )
end

# ── Dosya grubu ──
watch_group = project.main_group.new_group(WATCH_TARGET_NAME, WATCH_FILES_DIR)

%w[AcilYardimWatchApp.swift ContentView.swift].each do |filename|
  file_ref = watch_group.new_file(filename)
  watch_target.source_build_phase.add_file_reference(file_ref)
end
watch_group.new_file('Info.plist')

# ── Runner target'ına Watch target'ı bağımlılık olarak ekle ──
runner_target = project.targets.find { |t| t.name == 'Runner' }
raise "Runner target bulunamadı!" unless runner_target

runner_target.add_dependency(watch_target)

# ── Embed Watch Content: Shell Script fazı (CopyFiles değil) ──
# Explicit input/output sayesinde Xcode döngüyü kırabiliyor.
existing_embed = runner_target.build_phases.find do |p|
  p.respond_to?(:name) && p.name == 'Embed Watch Content'
end

unless existing_embed
  embed_script = project.new(Xcodeproj::Project::Object::PBXShellScriptBuildPhase)
  embed_script.name          = 'Embed Watch Content'
  embed_script.shell_path    = '/bin/sh'
  embed_script.shell_script  = <<~'BASH'
    WATCH_APP="${BUILT_PRODUCTS_DIR}/AcilYardim Watch App.app"
    DEST="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Watch"
    if [ -d "$WATCH_APP" ]; then
      mkdir -p "$DEST"
      cp -Rf "$WATCH_APP" "$DEST/"
      echo "[embed_watch] Watch app kopyalandı: $DEST"
    else
      echo "[embed_watch] Watch app bulunamadı, atlanıyor: $WATCH_APP"
    fi
  BASH

  # Input/output tanımları döngüyü kırıyor
  embed_script.input_paths  = ["$(BUILT_PRODUCTS_DIR)/AcilYardim Watch App.app"]
  embed_script.output_paths = ["$(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Watch/AcilYardim Watch App.app"]

  # Thin Binary'den ÖNCE ekle
  thin_binary_index = runner_target.build_phases.index do |p|
    p.respond_to?(:shell_script) &&
    p.shell_script.to_s.include?('Thin Binary')
  end

  if thin_binary_index
    runner_target.build_phases.insert(thin_binary_index, embed_script)
    puts "[watch_setup] Embed fazı Thin Binary'den önce eklendi (index: #{thin_binary_index})"
  else
    runner_target.build_phases << embed_script
    puts "[watch_setup] Embed fazı sona eklendi"
  end
end

project.save
puts "[watch_setup] Watch target başarıyla eklendi."
