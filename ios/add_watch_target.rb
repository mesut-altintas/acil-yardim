#!/usr/bin/env ruby
# Watch App target'ı Xcode projesine + scheme'e ekler.
# İdempotent: target zaten varsa hiçbir şey yapmaz.

require 'xcodeproj'

PROJECT_PATH      = 'ios/Runner.xcodeproj'
SCHEME_PATH       = 'ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme'
WATCH_TARGET_NAME = 'AcilYardim Watch App'
WATCH_BUNDLE_ID   = 'com.example.acilYardim.watchapp'
WATCH_FILES_DIR   = 'AcilYardim Watch App'

project = Xcodeproj::Project.open(PROJECT_PATH)

# İdempotent kontrol
if project.targets.any? { |t| t.name == WATCH_TARGET_NAME }
  puts "[watch_setup] Target '#{WATCH_TARGET_NAME}' zaten mevcut, atlanıyor."
  exit 0
end

puts "[watch_setup] Watch target oluşturuluyor..."

# ── 1. Ürün referansı ──
watch_product = project.new(Xcodeproj::Project::Object::PBXFileReference)
watch_product.path               = "#{WATCH_TARGET_NAME}.app"
watch_product.source_tree        = 'BUILT_PRODUCTS_DIR'
watch_product.include_in_index   = '0'
watch_product.explicit_file_type = 'wrapper.application'
project.products_group << watch_product

# ── 2. PBXNativeTarget ──
watch_target = project.new(Xcodeproj::Project::Object::PBXNativeTarget)
watch_target.name              = WATCH_TARGET_NAME
watch_target.product_name      = WATCH_TARGET_NAME
watch_target.product_type      = 'com.apple.product-type.application.watchapp2'
watch_target.product_reference = watch_product
project.targets << watch_target

puts "[watch_setup] Watch target UUID: #{watch_target.uuid}"

# ── 3. Build konfigürasyonları ──
config_list = project.new(Xcodeproj::Project::Object::XCConfigurationList)
config_list.default_configuration_name       = 'Release'
config_list.default_configuration_is_visible = '0'

%w[Debug Release Profile].each do |config_name|
  config = project.new(Xcodeproj::Project::Object::XCBuildConfiguration)
  config.name = config_name
  config.build_settings = {
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
    'SWIFT_OPTIMIZATION_LEVEL'              => config_name == 'Debug' ? '-Onone' : '-O',
    'DEBUG_INFORMATION_FORMAT'              => config_name == 'Debug' ? 'dwarf' : 'dwarf-with-dsym',
  }
  config_list.build_configurations << config
end
watch_target.build_configuration_list = config_list

# ── 4. Build fazları (minimal — sadece Sources, Resources, Frameworks) ──
sources_phase   = project.new(Xcodeproj::Project::Object::PBXSourcesBuildPhase)
resources_phase = project.new(Xcodeproj::Project::Object::PBXResourcesBuildPhase)
frameworks_phase = project.new(Xcodeproj::Project::Object::PBXFrameworksBuildPhase)
watch_target.build_phases.concat([sources_phase, resources_phase, frameworks_phase])

# ── 5. Dosya grubu + Swift kaynakları ──
watch_group = project.main_group.new_group(WATCH_TARGET_NAME, WATCH_FILES_DIR)

%w[AcilYardimWatchApp.swift ContentView.swift].each do |filename|
  file_ref   = watch_group.new_file(filename)
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.file_ref = file_ref
  sources_phase.files << build_file
  puts "[watch_setup] Kaynak eklendi: #{filename}"
end
watch_group.new_file('Info.plist')

# ── 6. Runner'a shell script embed fazı ekle (input/output tanımlı — döngü önler) ──
runner_target = project.targets.find { |t| t.name == 'Runner' }
raise "Runner target bulunamadı!" unless runner_target

existing_embed = runner_target.build_phases.find do |p|
  p.respond_to?(:name) && p.name == 'Embed Watch Content'
end

unless existing_embed
  embed_script = project.new(Xcodeproj::Project::Object::PBXShellScriptBuildPhase)
  embed_script.name         = 'Embed Watch Content'
  embed_script.shell_path   = '/bin/sh'
  embed_script.shell_script = <<~'BASH'
    WATCH_APP="${BUILT_PRODUCTS_DIR}/AcilYardim Watch App.app"
    DEST="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Watch"
    if [ -d "$WATCH_APP" ]; then
      mkdir -p "$DEST"
      cp -Rf "$WATCH_APP" "$DEST/"
      echo "[embed_watch] Kopyalandı: $DEST"
    else
      echo "[embed_watch] Watch app bulunamadı: $WATCH_APP"
      exit 0
    fi
  BASH
  embed_script.input_paths  = ["$(BUILT_PRODUCTS_DIR)/AcilYardim Watch App.app"]
  embed_script.output_paths = ["$(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Watch/AcilYardim Watch App.app"]

  thin_binary_index = runner_target.build_phases.index do |p|
    p.respond_to?(:shell_script) && p.shell_script.to_s.include?('Thin Binary')
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
puts "[watch_setup] Proje kaydedildi."

# ── 7. Runner.xcscheme'e Watch target'ı ekle ──
# buildImplicitDependencies=YES ile scheme'deki target'lar derlenir.
# add_dependency() kullanmıyoruz — "Multiple commands produce" hatasını önlemek için.
puts "[watch_setup] Scheme güncelleniyor: #{SCHEME_PATH}"

scheme_xml = File.read(SCHEME_PATH)

# Zaten eklenmiş mi?
if scheme_xml.include?(WATCH_TARGET_NAME)
  puts "[watch_setup] Watch target zaten scheme'de, atlanıyor."
else
  watch_entry = <<~XML
        <BuildActionEntry
           buildForTesting = "NO"
           buildForRunning = "NO"
           buildForProfiling = "NO"
           buildForArchiving = "YES"
           buildForAnalyzing = "NO">
           <BuildableReference
              BuildableIdentifier = "primary"
              BlueprintIdentifier = "#{watch_target.uuid}"
              BuildableName = "#{WATCH_TARGET_NAME}.app"
              BlueprintName = "#{WATCH_TARGET_NAME}"
              ReferencedContainer = "container:Runner.xcodeproj">
           </BuildableReference>
        </BuildActionEntry>
  XML

  # Runner BuildActionEntry'sinden hemen ÖNCE ekle
  scheme_xml.sub!(
    %r{(\s*</BuildActionEntries>)},
    "#{watch_entry.rstrip}\n\\1"
  )

  File.write(SCHEME_PATH, scheme_xml)
  puts "[watch_setup] Watch target scheme'e eklendi."
end

puts "[watch_setup] Tamamlandı."
