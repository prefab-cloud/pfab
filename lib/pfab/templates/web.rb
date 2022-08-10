module Pfab
  module Templates
    class Web < Base
      def write_to(f)
        if get("host").nil?
          puts "No host to deploy to for #{@data['deployed_name']}. Skipping."
        else
          f << YAML.dump(service.deep_stringify_keys)
          f << YAML.dump(ingress.deep_stringify_keys)
          f << YAML.dump(deployment.deep_stringify_keys)
        end
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
            },
            annotations: service_annotations,
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

      def service_annotations
        h = {}
        h["traefik.ingress.kubernetes.io/service.serversscheme"] = "h2c" if get("protocol") == "h2c"
        h
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
            tls: tls_hosts
          },
        }
      end

      def tls_hosts
        hosts.map do |host|
          {
            hosts: [host],
            secretName: get("tls_cert_secret")
          }
        end
      end

      def hosts
        get("host").split(",")
      end

      def rules
        hosts.map do |host|
          {
            host: host,
            http: {
              paths: [
                {
                  path: "/",
                  pathType: "Prefix",
                  backend: {
                    service: {
                      name: @data['deployed_name'],
                      port: {
                        name: "http"
                      }
                    }
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
          "traefik.ingress.kubernetes.io/router.entrypoints" => "websecure",
          "traefik.ingress.kubernetes.io/router.tls" => "true"
        }
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

      def application_type
        "web"
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
              "application-type" => application_type,
              "deploy-id" => deploy_id,
              "tags.datadoghq.com/env": @data['env'],
              "tags.datadoghq.com/service": @data['deployed_name'],
              "tags.datadoghq.com/service": @data['sha']
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
                  "tags.datadoghq.com/env": @data['env'],
                  "tags.datadoghq.com/service": @data['deployed_name'],
                  "tags.datadoghq.com/version": @data['sha']
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
                    volumeMounts: [
                      {
                        name: "apmsocketpath",
                        mountPath: "/var/run/datadog"
                      }
                    ]
                  }
                ],
                volumes: [
                  {
                    name: "apmsocketpath",
                    hostPath: {
                      path: "/var/run/datadog/",
                    }
                  }
                ],
              },
            },
          },
        }
      end
    end
  end
end
