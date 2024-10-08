# frozen_string_literal: true


module Pfab
  module Templates
    class LongRunningProcess < Pfab::Templates::Base
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

      def probes

        if application_type == "web" || get("probesEnabled")
          return {
            livenessProbe: livenessProbe,
            readinessProbe: readinessProbe,
            startupProbe: startupProbe,
          }
        end
        puts "probes are disabled, set `probesEnabled: true` to enable"
        return {

        }

      end


      def rolling_update_strategy
        {
          type: "RollingUpdate",
          rollingUpdate: {
            maxSurge: get("maxSurge") || 1,
            maxUnavailable: get("maxUnavailable") || 0,
          }
        }
      end






    end



  end
end

