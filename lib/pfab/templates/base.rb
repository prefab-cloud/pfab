require 'securerandom'

module Pfab
  module Templates
    class Base
      def initialize(data)
        @data = data
      end

      def image_name
        "#{@data['container_repository']}/#{@data['image_name']}:#{@data['sha']}"
      end

      def app_vars
        @data["application_yaml"]["deployables"][@data["props"][:deployable]]
      end

      def get(key)
        app_vars.dig(@data["env"], key) || app_vars[key]
      end

      def get_namespace
        @data['namespace']
      end

      def get_command()
        cmd = get("command")
        if cmd.kind_of?(Array)
          return cmd
        end
        return cmd.split(" ")
      end

      def cpu(req_type)
        default_cpu_string = @data["config"]["default_cpu_string"] || "50m/250m"
        (request, limit) = (get("cpu") || default_cpu_string).split("/")
        req_type == :limit ? limit : request
      end

      def memory(req_type)
        default_memory_string = @data["config"]["default_memory_string"] || "256Mi/500Mi"
        (request, limit) = (get("memory") || default_memory_string).split("/")
        req_type == :limit ? limit : request
      end

      def resources
        {
          requests: {
            cpu: cpu(:request),
            memory: memory(:request),
          },
          limits: {
            cpu: cpu(:limit),
            memory: memory(:limit),
          }
        }
      end

      # overridden in subtypes
      def application_type
        "base"
      end

      def deploy_id
        @data['deployed_name']
      end

      def deploy_unique_id
        @data['sha'] + "-" + @data['application_yaml_hash'][0,8]
      end

      def env_from
        env_from = []
        env_from << @data.dig("application_yaml", :env_from)
        env_from << @data.dig("application_yaml", @data["env"], :env_from)
        env_from.flatten!
        env_from.compact!
        env_from.empty? ? nil : env_from
      end

      def env_vars
        env_vars = { "DEPLOYED_NAME" => { value: @data['deployed_name'] },
                     "DEPLOY_ID" => { value: deploy_id }, # currently this is the same as deployed_name
                     "DEPLOY_FAMILY" => { value: @data['application'] },
                     "POD_ID" => { valueFrom: { fieldRef: { fieldPath: 'metadata.name' } } },
                     "SPEC_NODENAME" => { valueFrom: { fieldRef: { fieldPath: 'spec.nodeName' } } },
                     "DD_ENV" => { valueFrom: { fieldRef: { fieldPath: "metadata.labels['tags.datadoghq.com/env']" } } },
                     "DD_SERVICE" => { valueFrom: { fieldRef: { fieldPath: "metadata.labels['tags.datadoghq.com/service']" } } },
                     "DD_VERSION" => { valueFrom: { fieldRef: { fieldPath: "metadata.labels['tags.datadoghq.com/version']" } } }
        }

        # load defaults
        load_env_vars(env_vars, @data.dig("application_yaml", :environment))
        load_secrets(env_vars, @data.dig("application_yaml", :env_secrets))

        # load env overrides
        load_env_vars(env_vars, @data.dig("application_yaml", @data["env"], :environment))
        load_secrets(env_vars, @data.dig("application_yaml", @data["env"], :env_secrets))


        #load more env overrides first at app
        load_env_vars(env_vars, app_vars[:environment])
        load_secrets(env_vars, app_vars[:env_secrets])
        #  then app/environment
        load_env_vars(env_vars, app_vars.dig(@data["env"], :environment))
        load_secrets(env_vars, app_vars.dig(@data["env"], :env_secrets))


        env_vars.map do |k, v|
          { name: k }.merge(v)
        end
      end

      def load_env_vars(env_vars, hash)
        (hash || {}).each do |env_var_name, v|
          if v.to_s.start_with? "field/"
            (_, field_name) = v.split("/")
            env_vars[env_var_name] = { valueFrom: {
              fieldRef: { fieldPath: field_name }
            } }
          elsif v.to_s.start_with? "configmap/"
             (_, configmap_name, key_name) = v.split("/")
             env_vars[env_var_name] = { valueFrom: {
               configMapKeyRef: { name: configmap_name, key: key_name }
             } }
          else
            env_vars[env_var_name] = { value: v }
          end
        end
      end

      def load_secrets(env_vars, hash)
        (hash || {}).each do |env_var_name, v|
          (ref, key) = v.split("/")
          env_vars[env_var_name] = {
            valueFrom: {
              secretKeyRef: {
                name: ref,
                key: key
              }
            } }
        end
      end


      def container_ports
        ports = []
        if app_vars["port"]
          ports.append ({
            name: "main",
            containerPort: app_vars["port"]
          })
        end
        %w[additionalPorts containerPorts].each do |key|
          if get(key)
            get(key).each do |name, number|
              ports.append(
                {name: name, containerPort: number}
              )
            end
          end
        end

        return ports
      end

      def sidecars
        get("sidecars") || []
      end

      def build_sidecar_resources(sidecar)
        return nil unless sidecar["resources"]

        resources = {}
        if sidecar["resources"]["requests"]
          resources[:requests] = {}
          resources[:requests][:cpu] = sidecar["resources"]["requests"]["cpu"] if sidecar["resources"]["requests"]["cpu"]
          resources[:requests][:memory] = sidecar["resources"]["requests"]["memory"] if sidecar["resources"]["requests"]["memory"]
        end
        if sidecar["resources"]["limits"]
          resources[:limits] = {}
          resources[:limits][:cpu] = sidecar["resources"]["limits"]["cpu"] if sidecar["resources"]["limits"]["cpu"]
          resources[:limits][:memory] = sidecar["resources"]["limits"]["memory"] if sidecar["resources"]["limits"]["memory"]
        end

        resources.empty? ? nil : resources
      end

      def build_sidecar_env(sidecar)
        # Start with base environment variables that all containers get
        base_env = env_vars.dup

        # If sidecar has additional env vars, merge them in (allowing overrides)
        if sidecar["env"]
          sidecar_env = sidecar["env"].map do |env_var|
            if env_var.is_a?(Hash)
              env_var.transform_keys(&:to_sym)
            elsif env_var.is_a?(String)
              # Handle simple string format like "KEY=value" or just "KEY"
              if env_var.include?("=")
                key, value = env_var.split("=", 2)
                { name: key, value: value }
              else
                { name: env_var }
              end
            end
          end.compact

          # Merge sidecar env vars, allowing them to override base vars
          env_hash = {}
          base_env.each { |e| env_hash[e[:name]] = e }
          sidecar_env.each { |e| env_hash[e[:name]] = e }
          env_hash.values
        else
          base_env
        end
      end

      def build_sidecar_ports(sidecar)
        return nil unless sidecar["ports"]

        sidecar["ports"].map do |port|
          if port.is_a?(Hash)
            result = {}
            result[:name] = port["name"] if port["name"]
            result[:containerPort] = port["containerPort"] if port["containerPort"]
            result[:protocol] = port["protocol"] if port["protocol"]
            result
          elsif port.is_a?(Integer)
            { containerPort: port }
          end
        end.compact
      end

      def build_sidecar_volume_mounts(sidecar)
        return nil unless sidecar["volumeMounts"]

        sidecar["volumeMounts"].map do |mount|
          result = {}
          result[:name] = mount["name"] if mount["name"]
          result[:mountPath] = mount["mountPath"] if mount["mountPath"]
          result[:readOnly] = mount["readOnly"] if mount.key?("readOnly")
          result[:subPath] = mount["subPath"] if mount["subPath"]
          result
        end
      end

      def sidecar_containers
        sidecars.map do |sidecar|
          container = {
            name: sidecar["name"],
            image: sidecar["image"],
            restartPolicy: "Always"  # Native sidecar support (K8s 1.28+)
          }

          container[:command] = sidecar["command"] if sidecar["command"]
          container[:args] = sidecar["args"] if sidecar["args"]
          container[:env] = build_sidecar_env(sidecar)
          container[:envFrom] = env_from  # Inherit ConfigMap/Secret references
          container[:resources] = build_sidecar_resources(sidecar)
          container[:ports] = build_sidecar_ports(sidecar)
          container[:volumeMounts] = build_sidecar_volume_mounts(sidecar)
          container[:imagePullPolicy] = sidecar["imagePullPolicy"] if sidecar["imagePullPolicy"]
          container[:securityContext] = sidecar["securityContext"].transform_keys(&:to_sym) if sidecar["securityContext"]

          container.compact
        end
      end

      def base_labels
        {
          application: @data['application'],
          "deployed-name" => @data['deployed_name'],
        }
      end

      def metadata_labels
        base_labels.merge({
          "application-type" => application_type,
          "deploy-id" => deploy_id,
        })
      end

      def datadog_labels
        labels = {
          "tags.datadoghq.com/env" => @data['env'],
          "tags.datadoghq.com/service" => @data['deployed_name'],
          "tags.datadoghq.com/version" => StyledYAML.double_quoted(@data['sha'])
        }
        labels["tags.datadoghq.com/family"] = @data['family'] if @data['family']
        labels
      end

      def full_labels
        metadata_labels.merge(datadog_labels)
      end

      def pod_labels
        base_labels.merge({
          "application-type" => application_type,
        }).merge(datadog_labels)
      end
    end
  end
end
