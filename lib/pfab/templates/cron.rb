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
            schedule: get("schedule"),
            successfulJobsHistoryLimit: 1,
            failedJobsHistoryLimit: 1,
            jobTemplate: {
              metadata: {
                name: "#{@data['deployed_name']}-#{@data['sha']}",
                namespace: get_namespace,
                labels: {
                  application: @data['application'],
                  "deployed-name" => @data['deployed_name'],
                  "application-type" => "cron",
                },
              },
              spec: {
                template: {
                  metadata: {
                    labels: {
                      application: @data['application'],
                      "deployed-name" => @data['deployed_name'],
                      "application-type" => "cron",
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
                        command: app_vars["command"].split(" "),
                        env: env_vars,
                        resources: resources,
                      },
                    ],
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
