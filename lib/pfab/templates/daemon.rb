module Pfab
  module Templates
    class Daemon < Base
      def write_to(f)
        f << StyledYAML.dump(deployment.deep_stringify_keys)
      end

      def application_type
        "daemon"
      end

      def deployment
        {
          kind: "Deployment",
          apiVersion: "apps/v1",
          metadata: {
            name: @data['deployed_name'],
            namespace: get_namespace,
            labels: {
              application: @data['application'],
              "deployed-name" => @data['deployed_name'],
              "application-type" => application_type,
              "deploy-id" => deploy_id,
              "tags.datadoghq.com/env": @data['env'],
              "tags.datadoghq.com/service": @data['deployed_name'],
              "tags.datadoghq.com/version": StyledYAML.double_quoted(@data['sha'])
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
                  "tags.datadoghq.com/env": @data['env'],
                  "tags.datadoghq.com/service": @data['deployed_name'],
                  "tags.datadoghq.com/version": StyledYAML.double_quoted(@data['sha'])
                },
              },
              spec: {
                serviceAccountName: get('serviceAccountName'),
                containers: [
                  {
                    image: image_name,
                    name: @data['deployed_name'],
                    command: get_command,
                    env: env_vars,
                    resources: resources,
                  }
                ]
              }.compact,
            },
          }.compact,
        }
      end
    end
  end
end
