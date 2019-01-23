module Pfab
  module Templates
    class Cron < Base
      def write_to(f)
        f << YAML.dump(job.deep_stringify_keys)
      end

      def job
        {
          apiVersion: "batch/v1beta1",
          kind: "CronJob",
          metadata: {
            name: "#{@data['deployed_name']}-#{@data['sha']}",
            namespace: @data['env'],
            labels: {
              application: @data['application'],
              "deployed-name" => @data['deployed_name'],
              "application-type" => "job",
            }
          },
          spec: {
            schedule: get("schedule"),
            successfulJobsHistoryLimit: 1,
            failedJobsHistoryLimit: 1,
            jobTemplate: {
              metadata: {
                name: "#{@data['deployed_name']}-#{@data['sha']}",
                namespace: @data['env'],
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
                backoffLimit: 2,
              },
            },
          },
        }
      end
    end
  end
end
