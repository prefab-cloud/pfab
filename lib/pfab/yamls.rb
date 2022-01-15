require 'pry'
module Pfab
  class Yamls

    def initialize(apps:, application_yaml:, image_name:, env:, sha:, config:)
      @apps = apps
      @base_data = {
        "env" => env.to_s,
        'image_name' => image_name,
        'sha' => sha,
        'container_repository' => config["container.repository"],
        'config' => config,
        'application' => application_yaml["name"],
        'application_yaml' => application_yaml
      }
    end

    def env_vars(app)
      template = Pfab::Templates::Base.new(data_for(app, @apps[app]))
      template.env_vars
    end

    def data_for(app, props)
      data = @base_data.clone
      data['props'] = props
      data['deployed_name'] = app
      data
    end

    def generate(keys)

      keys.each do |key|
        props = @apps[key]
        data = data_for(key, props)

        filename = ".application-k8s-#{data["env"]}-#{key}.yaml"
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
