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
        "#{@data['application']}.#{application_type}.#{@data['deployed_name']}"
      end

      def env_vars
        env_vars = { "DEPLOYED_NAME" => { value: @data['deployed_name'] },
                     "DEPLOY_ID" => { value: deploy_id },
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
    end
  end
end
