module Pfab
  module Templates
    class Job < Base
      def write_to(f)
        f << YAML.dump(job.deep_stringify_keys)
      end

      def job
        {
          kind: "Pod",
          apiVersion: "v1",
          metadata: {
            name: "#{@data['deployed_name']}-#{@data['sha']}",
            namespace: @data['env'],
            labels: {
              application: @data['application'],
              "deployed-name" => @data['deployed_name'],
            }
          },
          spec: {
            containers: [
              {
                image: image_name,
                name: @data['deployed_name'],
                command: app_vars["command"].split(" "),
                env: env_vars,
                resources: {
                  requests: {
                    cpu: @data["cpu"] || "50m",
                    memory: @data["memory"] || "256Mi",
                  },
                  limits: {
                    cpu: @data["cpu"] || "250m",
                    memory: @data["memory"] || "256Mi",
                  },
                },
              }
            ]
          }
        }
      end
    end
  end
end
