module Pfab
  module Templates
    class Web < Base
      def write_to(f)
        f << YAML.dump(service.deep_stringify_keys)
        f << YAML.dump(ingress.deep_stringify_keys)
        f << YAML.dump(deployment.deep_stringify_keys)
      end

      def service
        {
          apiVersion: "v1",
          kind: "Service",
          metadata: {
            name: @data['deployed_name'],
            namespace: @data['env'],
            labels: {
              application: @data['application'],
              "deployed-name" => @data['deployed_name'],
            }
          },
          spec: {
            selector: {
              "deployed-name" => @data['deployed_name'],
            },
            ports: [
              {
                name: "http",
                port: 80,
                targetPort: 3000,
              }
            ]
          }
        }
      end

      def ingress
        {
          apiVersion: "extensions/v1beta1",
          kind: "Ingress",
          metadata: {
            name: "ingress-#{@data['deployed_name']}",
            namespace: @data['env'],
            labels: {
              application: @data['application'],
              "deployed-name" => @data['deployed_name'],
            },
            annotations: ingress_annotations,
          },
          spec: {
            rules: [
              {
                host: get("host"),
                http: {
                  paths: [
                    {
                      path: "/",
                      backend: {
                        serviceName: @data['deployed_name'],
                        servicePort: "http",
                      },
                    },
                  ],
                },
              },
            ],
          },
        }
      end

      def ingress_annotations
        {
          "kubernetes.io/ingress.class" => "traefik",
          "traefik.frontend.passHostHeader" => "false",
          "traefik.frontend.priority" => "1",
          "traefik.frontend.entryPoints" => "https",
          "traefik.protocol" => "http",
          "traefik.frontend.headers.SSLRedirect" => "true",
          "traefik.docker.network" => "traefik",
        }
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
              "application-type" => "web",
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
              type: "RollingUpdate",
              rollingUpdate: {
                maxSurge: 1,
                maxUnavailable: 0,
              }
            },
            revisionHistoryLimit: 5,
            progressDeadlineSeconds: 120,
            template: {
              metadata: {
                labels: {
                  application: @data['application'],
                  "deployed-name" => @data['deployed_name'],
                  "application-type" => "web",
                },
              },
              spec: {
                containers: [
                  {
                    image: image_name,
                    name: @data['deployed_name'],
                    command: get("command").split(" "),
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
                    livenessProbe: {
                      httpGet: {
                        path: get("health_check_path") || "/",
                        port: get("port"),
                      },
                      initialDelaySeconds: 5,
                    },
                    readinessProbe: {
                      httpGet: {
                        path: get("health_check_path") || "/",
                        port: get("port"),
                      },
                      initialDelaySeconds: 5,
                    },
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
