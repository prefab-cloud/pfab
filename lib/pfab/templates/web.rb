require "rubygems/safe_yaml"

module Pfab
  LABEL_DEPLOY_UNIQUE_ID = "deploy-unique-id"
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
          if get("replicas") || 1 > 1
            f << StyledYAML.dump(pod_disruption_budget.deep_stringify_keys)
          end
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
                port: app_vars["service_listen_port"] || 80,
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

      def pod_disruption_budget
        pdb = {
          apiVersion: "policy/v1",
          kind: "PodDisruptionBudget",
          metadata:  {
            name: "#{@data['deployed_name']}-pdb",
            namespace: get_namespace()
          },
          spec: {
            minAvailable: 1,
            selector: {
            matchLabels: {
              application: @data['application'],
              "deployed-name" => @data['deployed_name'],
              "application-type" => application_type
              }
            }
          }
        }
        return pdb
      end
      ANTI_AFFINITY_TYPES = %w[disabled required preferred]
      ANTI_AFFINITY_MODE = 'antiAffinityMode'
      ANTI_AFFINITY_PREFERRED_MODE_WEIGHT = 'antiAffinityPreferredModeWeight'
      ZONE_ANTI_AFFINITY_MODE = 'zoneAntiAffinityMode'
      ZONE_ANTI_AFFINITY_PREFERRED_MODE_WEIGHT = 'zoneAntiAffinityPreferredModeWeight'


      def anti_affinity
        return host_anti_affinity
      end


      def host_anti_affinity
        anti_affinity_builder(ANTI_AFFINITY_MODE, ANTI_AFFINITY_PREFERRED_MODE_WEIGHT, "kubernetes.io/hostname")
      end


      def topology_spread_constraints
        waiveTopologySpreadConstraints = get("waiveTopologySpreadConstraints") || false

        schedulingRule = waiveTopologySpreadConstraints ? "ScheduleAnyway" : "DoNotSchedule"

        zone_constraint = {
          maxSkew: 1,
          topologyKey: "topology.kubernetes.io/zone",
          whenUnsatisfiable: schedulingRule,
          labelSelector: labelSelector
        }
        host_constraint = {
          maxSkew: 1,
          topologyKey: "kubernetes.io/hostname",
          whenUnsatisfiable: schedulingRule,
          labelSelector: labelSelector

        }
        [zone_constraint, host_constraint]
      end



      def labelSelector
        {
          matchExpressions: [
          {
            key: "deployed-name",
            operator: "In",
            values: [
              @data['deployed_name']
            ]
          },
          {
            key: LABEL_DEPLOY_UNIQUE_ID,
            operator: "In",
            values: [
              StyledYAML.double_quoted(deploy_unique_id)
            ]
          }
        ]
        }
      end

      def anti_affinity_builder(key, weight_key, topology_key)
        antiAffinityMode = get(key) || "disabled"
        if antiAffinityMode
          affinitySelector = {
            topologyKey: topology_key,
            labelSelector: labelSelector,
          }

          return case antiAffinityMode
                 when "disabled"
                   puts "antiAffinityMode is set to disabled, skipping"
                   {}
                 when "required"
                   {
                     podAntiAffinity: {
                       requiredDuringSchedulingIgnoredDuringExecution: [
                         affinitySelector
                       ] } }
                 when "preferred"
                   { podAntiAffinity: {
                     preferredDuringSchedulingIgnoredDuringExecution: [
                       {
                         weight: app_vars[weight_key] || 100,
                         podAffinityTerm: affinitySelector
                       }
                     ]
                   }
                   }
                 else
                   raise "Unexpected value #{antiAffinityMode} specified for `#{key}`. Valid selections are #{ANTI_AFFINITY_TYPES}"
                 end
        end
        return {}
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
        ports = container_ports()

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
              LABEL_DEPLOY_UNIQUE_ID: StyledYAML.double_quoted(deploy_unique_id),
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
                  LABEL_DEPLOY_UNIQUE_ID => StyledYAML.double_quoted(deploy_unique_id),
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
                    envFrom: env_from,
                    resources: resources,
                    ports: ports,
                    livenessProbe: livenessProbe,
                    readinessProbe: readinessProbe,
                    startupProbe: startupProbe,
                    lifecycle: lifecycle,
                    volumeMounts: volume_mounts
                  }.compact
                ],
                topologySpreadConstraints: topology_spread_constraints,
                volumes: volumes
              }.compact,
            },
          }.compact,
        }.compact
      end
    end
  end
end
