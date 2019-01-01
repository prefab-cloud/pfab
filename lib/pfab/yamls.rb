require 'pry'
module Pfab
  class Yamls
    def self.generate_for(apps:, application_yaml:, image_name:, env:, sha:, config:)

      apps.map do |app, props|
        puts app

        data = {
          "env" => env.to_s,
          'image_name' => image_name,
          'sha' => sha,
          'container_repository' => config["container.repository"],
          'config' => config,
          'props' => props,
          'deployed_name' => app,
          'application' => application_yaml["name"],
          'application_yaml' => application_yaml
        }

        filename = ".application-k8s-#{env}-#{app}.yaml"
        File.open(filename, "w") do |f|
          case props[:deployable_type]
          when "web" then
            processed = Pfab::Templates::Web.new(data).write_to(f)
          when "job" then
            processed = Pfab::Templates::Job.new(data).write_to(f)
          when "daemon" then
            processed = Pfab::Templates::Daemon.new(data).write_to(f)
          end
        end
        filename
      end

    end


  end
end
