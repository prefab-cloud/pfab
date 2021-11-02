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
                targetPort: get("port"),
              }
            ]
          }
        }
      end

      def ingress
        {
          apiVersion: "networking.k8s.io/v1",
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
            rules: rules,
          },
        }
      end

      def rules
        hosts = get("host").split(",")
        hosts.map do |host|
          {
            host: host,
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
          }
        end
      end

      def ingress_annotations
        h = {
          "kubernetes.io/ingress.class" => "traefik",
          "traefik.frontend.passHostHeader" => "false",
          "traefik.frontend.priority" => "1",
          "traefik.frontend.entryPoints" => "https",
          "traefik.protocol" => get("protocol") || "http",
          "traefik.frontend.headers.SSLRedirect" => "true",
          "traefik.docker.network" => "traefik",
        }
        h["ingress.kubernetes.io/protocol"] = "h2c" if get("protocol") == "h2c"
        h
      end

      def default_probe
        {
          httpGet: {
            path: get("health_check_path") || "/",
            port: get("port"),
          },
          initialDelaySeconds: 15,
          timeoutSeconds: 3
        }
      end

      def livenessProbe
        get("livenessProbe") || default_probe
      end

      def readinessProbe
        get("readinessProbe") || default_probe
      end

      def deployment
        {
          kind: "Deployment",
          apiVersion: "apps/v1",
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
                    resources: resources,
                    livenessProbe: livenessProbe,
                    readinessProbe: readinessProbe,
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
