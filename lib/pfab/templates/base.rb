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
        app_vars[@data["env"]][key] || app_vars[key]
      end

      def env_vars

        env_vars = [
          { name: "DEPLOYED_NAME", value: @data['deployed_name'] }
        ]

        load_env_vars(env_vars, @data["application_yaml"][:environment])
        load_env_vars(env_vars, @data["application_yaml"][@data["env"]][:environment])

        load_secrets(env_vars, @data["application_yaml"][:env_secrets])
        load_secrets(env_vars, @data["application_yaml"][@data["env"]][:env_secrets])

        env_vars
      end

      def load_env_vars(env_vars, hash)
        (hash || {}).each do |env_var_name, v|
          env_vars << { name: env_var_name, value: v }
        end
      end

      def load_secrets(env_vars, hash)
        (hash || {}).each do |env_var_name, v|
          (ref, key) = v.split("/")
          env_vars << { name: env_var_name,
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
