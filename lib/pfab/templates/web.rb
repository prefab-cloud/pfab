require "rubygems/safe_yaml"

module Pfab
  module Templates
    class Web < Base
      def write_to(f)
        if get("host").nil?
          puts "No host to deploy to for #{@data['deployed_name']}. Skipping."
        else
          f << StyledYAML.dump(service.deep_stringify_keys)
          if not app_vars.has_key?('generateIngressEnabled') || app_vars['generateIngressEnabled']
            f << StyledYAML.dump(ingress.deep_stringify_keys)
          else
            puts "skipping ingress because ingress_disabled = #{@data['generateIngressEnabled']}"
          end
          f << StyledYAML.dump(deployment.deep_stringify_keys)
        end
      end

      def service
        {
          apiVersion: "v1",
          kind: "Service",
          metadata: {
            name: @data['deployed_name'],
            namespace: get_namespace,
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
                targetPort: app_vars["port"],
                appProtocol: app_vars["appProtocol"]
              }.compact
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
            namespace: get_namespace,
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

      def startupProbe
        get("startupProbe") || default_probe
      end

      def lifecycle
        get("lifecycle")
      end

      def application_type
        "web"
      end

      def deployment
        secret_mounts = get("secretMounts") || []
        volume_mounts = []
        volumes = []
        secret_mounts.each do |secret_mount|
          volumes.append({
                           name: secret_mount['name'],
                           secret: { secretName: secret_mount['secretName'] }
                         })
          volume_mounts.append({
                                 name: secret_mount['name'],
                                 mountPath: secret_mount['path'],
                                 readOnly: secret_mount['readOnly'] || true
                               })
        end

        if get("datadogVolumeMountEnabled")
          datadog_volume_name = "ddsocket"
          datadog_path = "/var/run/datadog"
          volumes.append({
                           name: datadog_volume_name,
                           hostPath: {
                            path: datadog_path
                           }
                         })
          volume_mounts.append(
            name: datadog_volume_name,
            mountPath: datadog_path,
            readOnly: true
          )
        end
        ports = [  {
                     name: "main",
                     containerPort: app_vars["port"]
                   }]
        if get("additionalPorts")
          get("additionalPorts").each do |name, number|
            ports.append(
              {name: name, containerPort: number}
            )
          end
        end

        {
          kind: "Deployment",
          apiVersion: "apps/v1",
          metadata: {
            name: @data['deployed_name'],
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
                  "tags.datadoghq.com/version": StyledYAML.double_quoted(@data['sha'])
                },
              },
              spec: {
                serviceAccountName: get('serviceAccountName'),
                terminationGracePeriodSeconds: get("terminationGracePeriodSeconds") || 30,
                containers: [
                  {
                    image: image_name,
                    name: @data['deployed_name'],
                    command: get_command,
                    env: env_vars,
                    resources: resources,
                    ports: ports,
                    livenessProbe: livenessProbe,
                    readinessProbe: readinessProbe,
                    startupProbe: startupProbe,
                    lifecycle: lifecycle,
                    volumeMounts: volume_mounts
                  }
                ],
                volumes: volumes
              }.compact,
            },
          }.compact,
        }
      end
    end
  end
end
