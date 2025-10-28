require "rubygems/safe_yaml"

module Pfab
  LABEL_DEPLOY_UNIQUE_ID = "deploy-unique-id"
  module Templates
    class Web < LongRunningProcess

      def get_replica_count
        raw_replicas = get("replicas")
        raw_replicas ? raw_replicas.to_i : 1
      end

      def write_to(f)
        if ingres_enabled? && get("host").nil?
          puts "No host to configure ingress for #{@data['deployed_name']}. Skipping deployment. add a host or generateIngressEnabled:false"
        else
          f << StyledYAML.dump(service.deep_stringify_keys)
          if ingres_enabled?
            f << StyledYAML.dump(ingress.deep_stringify_keys)
          else
            puts "skipping ingress because ingress_disabled = #{@data['generateIngressEnabled']}"
          end
          f << StyledYAML.dump(deployment.deep_stringify_keys)
          f << StyledYAML.dump(pod_disruption_budget.deep_stringify_keys)
        end
      end

      def ingres_enabled?
        if not app_vars.has_key?('generateIngressEnabled') || app_vars['generateIngressEnabled']
          return true
        end
        return false
      end

      def service
        {
          apiVersion: "v1",
          kind: "Service",
          metadata: {
            name: @data['deployed_name'],
            namespace: get_namespace,
            labels: base_labels,
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
            labels: base_labels,
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

      def lifecycle
        get("lifecycle")
      end


      def application_type
        "web"
      end

      def pod_disruption_budget
        replica_count = get_replica_count()
        
        # For single replica deployments, allow the pod to be disrupted
        # For multi-replica deployments, ensure at least 50% of pods remain available
        disruption_spec = if replica_count == 1
          { maxUnavailable: 1 }
        else
          { minAvailable: (replica_count * 0.5).floor }
        end
        
        pdb = {
          apiVersion: "policy/v1",
          kind: "PodDisruptionBudget",
          metadata:  {
            name: "#{@data['deployed_name']}-pdb",
            namespace: get_namespace()
          },
          spec: disruption_spec.merge({
            selector: {
              matchLabels: {
                application: @data['application'],
                "deployed-name" => @data['deployed_name'],
                "application-type" => application_type
              }
            }
          })
        }
        return pdb
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
            labels: full_labels.merge({
              LABEL_DEPLOY_UNIQUE_ID => StyledYAML.double_quoted(deploy_unique_id),
            })
          },
          spec: {
            replicas: get("replicas") || 1,
            selector: {
              matchLabels: {
                "deployed-name" => @data['deployed_name'],
              },
            },
            strategy: rolling_update_strategy,
            revisionHistoryLimit: 5,
            progressDeadlineSeconds: get("progressDeadlineSeconds") || 600,
            template: {
              metadata: {
                labels: pod_labels.merge({
                  LABEL_DEPLOY_UNIQUE_ID => StyledYAML.double_quoted(deploy_unique_id),
                }),
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
                    lifecycle: lifecycle,
                    volumeMounts: volume_mounts
                  }.merge(probes()).compact
                ] + sidecar_containers,
                topologySpreadConstraints: get_replica_count > 1 ? topology_spread_constraints : [],
                volumes: volumes
              }.compact,
            },
          }.compact,
        }.compact
      end
    end
  end
end
