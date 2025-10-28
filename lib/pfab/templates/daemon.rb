module Pfab
  module Templates
    class Daemon < LongRunningProcess
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
            labels: full_labels
          },
          spec: {
            replicas: get("replicas") || 1,
            selector: {
              matchLabels: {
                "deployed-name" => @data['deployed_name'],
              },
            },
            strategy: rolling_update_strategy,
            revisionHistoryLimit: 5,
            template: {
              metadata: {
                labels: pod_labels,
              },
              spec: {
                serviceAccountName: get('serviceAccountName'),
                containers: [
                  {
                    image: image_name,
                    name: @data['deployed_name'],
                    command: get_command,
                    env: env_vars,
                    envFrom: env_from,
                    resources: resources,
                    ports: container_ports()
                  }.merge(probes()).compact
                ] + sidecar_containers
              }.compact,
            },
          }.compact,
        }
      end
    end
  end
end
