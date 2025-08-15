require 'pry'
module Pfab
  class Yamls

    def initialize(apps:, application_yaml:, image_name:, env:, sha:, config:, application_yaml_hash:)
      @apps = apps
      namespace = application_yaml.dig(env.to_s, "namespace") || application_yaml["namespace"]
      raise "No namespace founds" unless namespace
      @base_data = {
        "env" => env.to_s,
        'image_name' => image_name,
        'sha' => sha,
        'container_repository' => config["container.repository"],
        'config' => config,
        'application' => application_yaml["name"],
        'family' => application_yaml["family"],
        'application_yaml' => application_yaml,
        'namespace' => namespace,
        'application_yaml_hash' => application_yaml_hash
      }
    end

    def env_vars(app)
      template = Pfab::Templates::Base.new(data_for(app, @apps[app]))
      template.env_vars
    end

    def env_from(app)
      template = Pfab::Templates::Base.new(data_for(app, @apps[app]))
      template.env_from
    end

    def data_for(app, props)
      data = @base_data.clone
      data['props'] = props
      data['deployed_name'] = app
      data
    end

    def namespace
      @base_data['namespace']
    end

    def generate(keys)
      #ensure the directory exists
      FileUtils.mkdir_p(FILES_DIR) unless Dir.exist?(FILES_DIR)
      keys.each do |key|
        props = @apps[key]
        data = data_for(key, props)

        filename = "#{FILES_DIR}/.application-k8s-#{data["env"]}-#{key}.yaml"
        File.open(filename, "w") do |f|
          case props[:deployable_type]
          when "web" then
            processed = Pfab::Templates::Web.new(data).write_to(f)
          when "job" then
            processed = Pfab::Templates::Job.new(data).write_to(f)
          when "daemon" then
            processed = Pfab::Templates::Daemon.new(data).write_to(f)
          when "cron" then
            processed = Pfab::Templates::Cron.new(data).write_to(f)
          end
        end
        filename
      end
    end
  end
end
