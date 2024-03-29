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
            ttlSecondsAfterFinished: get('ttlSecondsAfterFinished'),
            completions: get('completions') || 1,
            parallelism: get('parallelism') || 1,
            template: {
              metadata: {
                name: "#{@data['deployed_name']}-#{@data['sha']}",
                namespace: get_namespace,
                labels: {
                  application: @data['application'],
                  "deployed-name" => @data['deployed_name'],
                  "application-type" => "job",
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
