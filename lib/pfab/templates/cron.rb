module Pfab
  module Templates
    class Cron < Base
      def write_to(f)
        f << StyledYAML.dump(job.deep_stringify_keys)
      end

      def application_type
        "cron"
      end

      def job
        {
          apiVersion: "batch/v1",
          kind: "CronJob",
          metadata: {
            name: "#{@data['deployed_name']}-#{@data['sha']}",
            namespace: get_namespace,
            labels: full_labels
          },
          spec: {
            schedule: get("schedule"),
            concurrencyPolicy: get("concurrencyPolicy") || 'Allow',
            successfulJobsHistoryLimit: 1,
            failedJobsHistoryLimit: 1,
            jobTemplate: {
              metadata: {
                name: "#{@data['deployed_name']}-#{@data['sha']}",
                namespace: get_namespace,
                labels: metadata_labels,
              },
              spec: {
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
                      },
                    ] + sidecar_containers,
                    restartPolicy: "Never",
                  }.compact,
                },
                backoffLimit: 2,
              },
            },
          },
        }
      end
    end
  end
end
