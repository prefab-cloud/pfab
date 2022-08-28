module Pfab
  module Templates
    class Job < Base
      def write_to(f)
        f << YAML.dump(job.deep_stringify_keys)
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
            namespace: @data['env'],
            labels: {
              application: @data['application'],
              "deployed-name" => @data['deployed_name'],
              "application-type" => application_type,
              "deploy-id" => deploy_id,
              "tags.datadoghq.com/env": @data['env'],
              "tags.datadoghq.com/service": @data['deployed_name'],
              "tags.datadoghq.com/version":"#{@data['sha']}"
            }
          },
          spec: {
            template: {
              metadata: {
                name: "#{@data['deployed_name']}-#{@data['sha']}",
                namespace: @data['env'],
                labels: {
                  application: @data['application'],
                  "deployed-name" => @data['deployed_name'],
                  "application-type" => "job",
                  "tags.datadoghq.com/env": @data['env'],
                  "tags.datadoghq.com/service": @data['deployed_name'],
                  "tags.datadoghq.com/version": "#{@data['sha']}"
                },
              },
              spec: {
                containers: [
                  {
                    image: image_name,
                    name: @data['deployed_name'],
                    command: app_vars["command"].split(" "),
                    env: env_vars,
                    resources: resources,
                  },
                ],
                restartPolicy: "Never",
              },
            },
            backoffLimit: 0,
          },
        }
      end
    end
  end
end
