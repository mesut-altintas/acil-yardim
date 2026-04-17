#!/usr/bin/env ruby
# Watch App target'ı Xcode projesine programatik olarak ekler.
# GitHub Actions macOS runner'ında çalışır.
# İdempotent: target zaten varsa hiçbir şey yapmaz.

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
    'PRODUCT_NAME'                         => WATCH_TARGET_NAME,
    'PRODUCT_BUNDLE_IDENTIFIER'            => WATCH_BUNDLE_ID,
    'SWIFT_VERSION'                        => '5.0',
    'WATCHOS_DEPLOYMENT_TARGET'            => '7.0',
    'TARGETED_DEVICE_FAMILY'               => '4',
    'SDKROOT'                              => 'watchos',
    'SUPPORTED_PLATFORMS'                  => 'watchos watchsimulator',
    'INFOPLIST_FILE'                       => "#{WATCH_FILES_DIR}/Info.plist",
    'SKIP_INSTALL'                         => 'YES',
    'ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES' => 'YES',
    'CODE_SIGN_STYLE'                      => 'Automatic',
    'DEVELOPMENT_TEAM'                     => '$(DEVELOPMENT_TEAM)',
    'ASSETCATALOG_COMPILER_APPICON_NAME'   => 'AppIcon',
    'LD_RUNPATH_SEARCH_PATHS'              => '$(inherited) @executable_path/Frameworks',
    'SWIFT_OPTIMIZATION_LEVEL'             => config.name == 'Debug' ? '-Onone' : '-O',
  )
end

# ── Dosya grubu ──
watch_group = project.main_group.new_group(WATCH_TARGET_NAME, WATCH_FILES_DIR)

# Swift kaynak dosyaları
%w[AcilYardimWatchApp.swift ContentView.swift].each do |filename|
  file_ref = watch_group.new_file(filename)
  watch_target.source_build_phase.add_file_reference(file_ref)
end

# Info.plist
watch_group.new_file('Info.plist')

# ── Runner target'ına Embed Watch Content fazı ekle ──
# Döngü hatası önlemek için "Thin Binary" fazından ÖNCE eklenmeli
runner_target = project.targets.find { |t| t.name == 'Runner' }
raise "Runner target bulunamadı!" unless runner_target

# Mevcut embed fazı var mı kontrol et
existing_embed = runner_target.build_phases.find do |p|
  p.is_a?(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase) &&
  p.name == 'Embed Watch Content'
end

unless existing_embed
  embed_phase = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
  embed_phase.name = 'Embed Watch Content'
  embed_phase.dst_path = '$(CONTENTS_FOLDER_PATH)/Watch'
  embed_phase.dst_subfolder_spec = '16'

  # "Thin Binary" fazını bul ve ondan ÖNCE ekle (döngü önleme)
  thin_binary_index = runner_target.build_phases.index do |p|
    p.respond_to?(:shell_script) &&
    p.shell_script.to_s.include?('Thin Binary')
  end

  if thin_binary_index
    runner_target.build_phases.insert(thin_binary_index, embed_phase)
    puts "[watch_setup] Embed fazı Thin Binary'den önce eklendi (index: #{thin_binary_index})"
  else
    runner_target.build_phases << embed_phase
    puts "[watch_setup] Embed fazı sona eklendi (Thin Binary bulunamadı)"
  end

  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.file_ref = watch_target.product_reference
  build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  embed_phase.files << build_file
end

project.save
puts "[watch_setup] Watch target başarıyla eklendi."
