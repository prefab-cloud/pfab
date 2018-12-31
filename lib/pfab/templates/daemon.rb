module Pfab
  module Templates
    class Daemon < Base
      def write_to(f)
        f << YAML.dump(deployment.deep_stringify_keys)
      end

      def deployment
        {
          kind: "Deployment",
          apiVersion: "extensions/v1beta1",
          metadata: {
            name: @data['deployed_name'],
            namespace: @data['env'],
            labels: {
              application: @data['application'],
              "deployed-name" => @data['deployed_name'],
              "application-type" => "daemon",
            }
          },
          spec: {
            replicas: get("replicas") || 1,
            selector: {
              matchLabels: {
                "deployed-name" => @data['deployed_name'],
              },
            },
            strategy: {
              type: "Recreate"
            },
            revisionHistoryLimit: 5,
            template: {
              metadata: {
                labels: {
                  application: @data['application'],
                  "deployed-name" => @data['deployed_name'],
                  "application-type" => "daemon",
                },
              },
              spec: {
                containers: [
                  {
                    image: image_name,
                    name: @data['deployed_name'],
                    command: get("command").split(" "),
                    env: env_vars,
                    resources: resources,
                  }
                ]
              },
            },
          },
        }
      end
    end
  end
end
