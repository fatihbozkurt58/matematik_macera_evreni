require 'fileutils'
require 'json'
require 'rexml/document'
require 'xcodeproj'

root = File.expand_path('..', __dir__)
project_path = File.join(root, 'ios', 'Runner.xcodeproj')
project = Xcodeproj::Project.open(project_path)
flavors = %w[dev staging prod]
base_names = %w[Debug Profile Release]
dev_plist_path = File.join(root, 'ios', 'Runner', 'Firebase', 'dev', 'GoogleService-Info.plist')
dev_android_path = File.join(root, 'android', 'app', 'src', 'dev', 'google-services.json')
dev_plist = Xcodeproj::Plist.read_from_path(dev_plist_path)
dev_android = JSON.parse(File.read(dev_android_path))
dev_web_client = dev_android.fetch('client').first.fetch('oauth_client').find { |client| client['client_type'] == 3 }
raise 'Missing dev Google OAuth client' unless dev_plist['CLIENT_ID'] && dev_plist['REVERSED_CLIENT_ID'] && dev_web_client

lists = [project.root_object.build_configuration_list]
lists.concat(project.targets.map(&:build_configuration_list))

lists.each do |list|
  base_names.each do |base_name|
    base = list.build_configurations.find { |config| config.name == base_name }
    raise "Missing #{base_name} configuration" unless base

    flavors.each do |flavor|
      name = "#{base_name}-#{flavor}"
      config = list.build_configurations.find { |item| item.name == name }
      unless config
        config = project.new(Xcodeproj::Project::Object::XCBuildConfiguration)
        config.name = name
        config.build_settings = base.build_settings.dup
        config.base_configuration_reference = base.base_configuration_reference
        list.build_configurations << config
      end

      next unless list == project.targets.find { |target| target.name == 'Runner' }&.build_configuration_list

      suffix = flavor == 'prod' ? '' : ".#{flavor}"
      config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = "com.fatihbozkurt.matematik#{suffix}"
      config.build_settings['APP_DISPLAY_NAME'] = flavor == 'prod' ? 'Matematik Evreni' : "Matematik Evreni #{flavor.capitalize}"
      config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
      if flavor == 'dev'
        config.build_settings['GOOGLE_CLIENT_ID'] = dev_plist['CLIENT_ID']
        config.build_settings['GOOGLE_REVERSED_CLIENT_ID'] = dev_plist['REVERSED_CLIENT_ID']
        config.build_settings['GOOGLE_SERVER_CLIENT_ID'] = dev_web_client['client_id']
      end
    end
  end
end

runner = project.targets.find { |target| target.name == 'Runner' }
raise 'Runner target missing' unless runner

unless runner.shell_script_build_phases.any? { |phase| phase.name == 'Select Firebase configuration' }
  phase = runner.new_shell_script_build_phase('Select Firebase configuration')
  phase.shell_script = <<~'SH'
    set -e
    FLAVOR="${CONFIGURATION#*-}"
    case "$FLAVOR" in dev|staging|prod) ;; *) echo "Unknown Firebase flavor: $CONFIGURATION" >&2; exit 1 ;; esac
    CONFIG_FILE="${PROJECT_DIR}/Runner/Firebase/${FLAVOR}/GoogleService-Info.plist"
    if [ ! -f "$CONFIG_FILE" ]; then
      echo "Missing Firebase configuration: $CONFIG_FILE" >&2
      exit 1
    fi
    cp "$CONFIG_FILE" "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/GoogleService-Info.plist"
  SH
  phase.show_env_vars_in_log = '0'
end

project.save

source_scheme = File.join(project_path, 'xcshareddata', 'xcschemes', 'Runner.xcscheme')
flavors.each do |flavor|
  scheme_path = File.join(project_path, 'xcshareddata', 'xcschemes', "#{flavor}.xcscheme")
  document = REXML::Document.new(File.read(source_scheme))
  REXML::XPath.each(document, '//*[@buildConfiguration]') do |node|
    node.attributes['buildConfiguration'] = "#{node.attributes['buildConfiguration']}-#{flavor}"
  end
  File.open(scheme_path, 'w') { |file| document.write(file, 2) }
end
