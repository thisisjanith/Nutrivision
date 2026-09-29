#!/usr/bin/env ruby
# One-off project surgery: adds the widget extension and watch app targets,
# entitlements and Info.plist keys. Idempotent-ish: aborts if targets exist.
#   gem install xcodeproj --user-install && ruby Scripts/add_extension_targets.rb
require 'xcodeproj'

proj = Xcodeproj::Project.open('NutriVision.xcodeproj')
abort('targets already exist') if proj.targets.any? { |t| t.name == 'NutriVisionWidgets' }

app = proj.targets.find { |t| t.name == 'NutriVision' }
team = 'H2SGDST2MQ'
bundle = 'Janith-Kavinda.NutriVision'
shared = %w[NutriVision/Services/DailySnapshot.swift NutriVision/Services/FastingActivityAttributes.swift NutriVision/Services/NutriIntents.swift]

# --- main app settings
app.build_configurations.each do |c|
  s = c.build_settings
  s['CODE_SIGN_ENTITLEMENTS'] = 'Config/NutriVision.entitlements'
  s['INFOPLIST_KEY_NSHealthShareUsageDescription'] = 'NutriVision reads your weight, steps and active energy to personalise your goals.'
  s['INFOPLIST_KEY_NSHealthUpdateUsageDescription'] = 'NutriVision saves the meals, water and weight you log to Apple Health.'
  s['INFOPLIST_KEY_NSSupportsLiveActivities'] = 'YES'
end

def configure(target, settings)
  target.build_configurations.each do |c|
    settings.each { |k, v| c.build_settings[k] = v }
  end
end

common = {
  'DEVELOPMENT_TEAM' => team,
  'SWIFT_VERSION' => '5.0',
  'CURRENT_PROJECT_VERSION' => '1',
  'MARKETING_VERSION' => '1.0',
  'GENERATE_INFOPLIST_FILE' => 'YES',
  'CODE_SIGN_STYLE' => 'Automatic',
  'SKIP_INSTALL' => 'YES',
}

# --- widget extension
widget = proj.new_target(:app_extension, 'NutriVisionWidgets', :ios, '17.0')
configure(widget, common.merge(
  'PRODUCT_BUNDLE_IDENTIFIER' => "#{bundle}.Widgets",
  'PRODUCT_NAME' => '$(TARGET_NAME)',
  'INFOPLIST_FILE' => 'NutriVisionWidgets/Info.plist',
  'INFOPLIST_KEY_CFBundleDisplayName' => 'NutriVision',
  'CODE_SIGN_ENTITLEMENTS' => 'Config/NutriVisionWidgets.entitlements',
  'TARGETED_DEVICE_FAMILY' => '1,2',
  'IPHONEOS_DEPLOYMENT_TARGET' => '17.0',
  'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks'],
))
wg = proj.main_group.new_group('NutriVisionWidgets', 'NutriVisionWidgets')
widget_refs = Dir['NutriVisionWidgets/*.swift'].sort.map { |f| wg.new_file(File.basename(f)) }
wg.new_file('Info.plist')
shared_refs = shared.map { |f| proj.main_group.new_reference(f) }
widget.add_file_references(widget_refs + shared_refs)

# --- watch app
watch = proj.new_target(:application, 'NutriVisionWatch', :watchos, '10.0')
configure(watch, common.merge(
  'PRODUCT_BUNDLE_IDENTIFIER' => "#{bundle}.watchkitapp",
  'PRODUCT_NAME' => 'NutriVisionWatch',
  'SDKROOT' => 'watchos',
  'SUPPORTED_PLATFORMS' => 'watchos watchsimulator',
  'TARGETED_DEVICE_FAMILY' => '4',
  'WATCHOS_DEPLOYMENT_TARGET' => '10.0',
  'INFOPLIST_KEY_WKApplication' => 'YES',
  'INFOPLIST_KEY_WKCompanionAppBundleIdentifier' => bundle,
  'INFOPLIST_KEY_CFBundleDisplayName' => 'NutriVision',
  'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon',
  'ENABLE_PREVIEWS' => 'YES',
  'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks'],
  'SKIP_INSTALL' => 'NO',
))
watch.build_configurations.each { |c| c.build_settings.delete('IPHONEOS_DEPLOYMENT_TARGET') }
wwg = proj.main_group.new_group('NutriVisionWatch', 'NutriVisionWatch')
watch_refs = Dir['NutriVisionWatch/*.swift'].sort.map { |f| wwg.new_file(File.basename(f)) }
watch.add_file_references(watch_refs + [proj.main_group.new_reference('NutriVision/Services/DailySnapshot.swift')])
assets = wwg.new_file('Assets.xcassets')
watch.resources_build_phase.add_file_reference(assets)

# --- embed into the iOS app
app.add_dependency(widget)
# The watch app is intentionally NOT embedded: an embedded watch app makes
# Xcode require the watchOS simulator runtime for every iPhone build. To ship
# it, add `app.add_dependency(watch)` and an 'Embed Watch Content' copy phase
# (dstSubfolderSpec 16, dstPath $(CONTENTS_FOLDER_PATH)/Watch).

ext_phase = app.new_copy_files_build_phase('Embed Foundation Extensions')
ext_phase.dst_subfolder_spec = '13'
ext_phase.add_file_reference(widget.product_reference).settings = { 'ATTRIBUTES' => %w[CodeSignOnCopy RemoveHeadersOnCopy] }

proj.save
puts 'done'
