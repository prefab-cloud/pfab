module Pfab
  module Templates
    class Job < Base
      def write_to(f)
        f << StyledYAML.dump(job.deep_stringify_keys)
      end

      def application_type
        "job"
      end

      def job
        {
          apiVersion: "batch/v1",
          kind: "Job",
          metadata: {
            name: "job-#{@data['deployed_name']}-#{@data['sha']}",
            namespace: get_namespace,
            labels: full_labels
          },
          spec: {
            ttlSecondsAfterFinished: get('ttlSecondsAfterFinished'),
            completions: get('completions') || 1,
            parallelism: get('parallelism') || 1,
            template: {
              metadata: {
                name: "#{@data['deployed_name']}-#{@data['sha']}",
                namespace: get_namespace,
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
                ],
                restartPolicy: "Never",
              }.compact,
            },
            backoffLimit: 0,
          }.compact,
        }
      end
    end
  end
end
