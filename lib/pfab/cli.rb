require "commander"
require "net/http"
require "yaml"
require "json"
require 'active_support/core_ext/hash/indifferent_access'
require 'styled_yaml'
require 'digest'
require 'open3'
require "fileutils"

module Pfab
  FILES_DIR = ".pfab"
  class CLI
    include Commander::Methods

    def run
      program :name, "pfab"
      program :version, Pfab::Version::STRING
      program :description, "k8s helper"

      if File.exist? "application.yaml"
        @application_yaml = YAML.load(File.read("application.yaml")).with_indifferent_access
        @application_yaml_hash = Digest::SHA256.hexdigest(@application_yaml.to_json)
      else
        raise "I need to be run in a directory with a application.yaml"
      end
      global_option("--verbose") { $verbose = true }
      $dryrun = false
      global_option("--dryrun") { $dryrun = true }
      $env = :staging
      global_option("-p") do
        puts "please use `-e production` next time!"
        $env = :production
      end
      global_option("-e", "--environment ENV", "specify target env") do |env_name|
        puts "Using environment #{env_name}"
        $env = env_name
      end
      global_option("-a", "--application_name APP_NAME", "run without prompting for app") do |app_name|
        $app_name = app_name
      end

      command :build do |c|
        c.syntax = "pfab build"
        c.summary = "build image"
        c.option "--force", "force build and push"
        c.option "--check", "just check if built"
        c.action do |_args, options|
          if cmd_build(force: options.force, checkonly: options.check)
            puts "Build succeeded"
          else
            raise "Build failed"
          end
        end
      end

      command :generate_yaml do |c|
        c.syntax = "pfab generate_yaml"
        c.summary = "build k8s yaml"
        c.action do
          cmd_generate_yaml
        end
      end
      command :apply do |c|
        c.syntax = "pfab apply"
        c.summary = "kubectl apply"
        c.action do
          cmd_apply
        end
      end

      command :shipit do |c|
        c.syntax = "pfab shipit"
        c.summary = "build, generate, apply"
        c.option "-t", "--timeout TIMEOUT", Integer, "timeout for rollout (default 360s)"
        c.option "-r", "--retries RETRIES", Integer, "number of retries for rollout (default 3)"
        c.option "-s", "--sleep SLEEP", Integer, "sleep duration between retries in seconds (default 5)"
        c.option "-g", "--tagged TAGGED", String, "target deployables tagged with TAGGED"

        c.action do |args, options|
          options.default timeout: 360, retries: 3, sleep: 5
          app_name = ""
          if options.tagged && options.tagged != ""
            app_name = "Apps tagged with #{options.tagged}"
          else
            app_name = get_app_name(all: true)
          end

          puts "Shipping #{app_name}"
          success = cmd_build
          if success
            cmd_generate_yaml
            cmd_apply(timeout: options.timeout, retries: options.retries, sleep_duration: options.sleep, tagged: options.tagged)
          else
            raise "Build failed"
          end
        end
      end

      command :logs do |c|
        c.syntax = "pfab logs"
        c.summary = "tail logs"
        c.description = "show me my logs`"
        c.example "tail logs of the first pod in staging",
                  "pfab logs"
        c.example "tail logs of the first pod in production",
                  "pfab -p logs"
        c.action do
          set_kube_context
          app_name = get_app_name

          first_pod = get_first_pod(app_name)

          kubectl("logs -f #{first_pod}")
        end
      end

      command :restart do |c|
        c.syntax = "pfab restart"
        c.summary = "rolling restart of a deployment"
        c.description = "rolling restart of a deployment"
        c.action do
          set_kube_context
          app_name = get_app_name

          kubectl "rollout restart deployment.apps/#{app_name}"
        end
      end

      command :exec do |c|
        c.option "-c", "--command command", "use with exec to run a command and exit. default is /bin/sh"
        c.syntax = "pfab exec [-- command to execute]'"
        c.summary = "kubectl exec into a  pod"
        c.description = "CLI to the Cloud"
        c.example "exec into the first pod in staging",
                  "pfab -e staging exec"
        c.example "exec into the first pod in production",
                  "pfab -p exec"
        c.action do |args, options|
          set_kube_context
          # Access the command line input after "--"
          additional_args = ARGV[ARGV.index('--') + 1..-1] if ARGV.include?('--')
          app_name = get_app_name
          first_pod = get_first_pod app_name
          kubectl "exec -it #{first_pod}", "-- #{additional_args ? additional_args.join(' ') : (options.command || '/bin/sh')}"
        end
      end

      command :status do |c|
        c.syntax = "pfab status"
        c.summary = "status of an app"
        c.description = "what's happening"
        c.example "what's happening in my app?",
                  "pfab status"
        c.example "what's happening in production",
                  "pfab status -p status"
        c.example "pick a single app",
                  "pfab status --pick "
        c.example "verbose mode",
                  "pfab status --verbose "
        c.example "watch deploy",
                  "pfab status --watch "
        c.option "--watch", "Watch"
        c.action do |_args, options|
          set_kube_context

          selector = "application=#{@application_yaml['name']}"

          if options.watch
            kubectl "get pods -l #{selector} -w"
          elsif $verbose
            kubectl "describe pods -l #{selector}"
          else
            kubectl "get ingresses,jobs,services,cronjobs,deployments,pods -l #{selector}"
          end
        end
      end

      command :run_local do |c|
        c.syntax = "pfab run_local"
        c.summary = "run an app LOCALLY"
        c.description = "run the application command with all env vars set"
        c.example "run a command locally",
                  "pfab run_local"
        c.option "-c", "--command COMMAND", "Run a command with the ENV vars of the selected app"
        c.action do |_args, options|
          $env = :development
          app_name = get_app_name(include_run_locals: true)
          puts "RUNNING THE FOLLOWING LOCALLY"

          env_vars = yy.env_vars(app_name).
            reject { |v| v.has_key? :valueFrom }

          env_var_string = env_vars.map { |item| "#{item[:name]}=\"#{item[:value]}\"" }.join(" ")
          options.default command: all_runnables[app_name][:command]

          puts_and_system "#{env_var_string} #{options.command}"
        end
      end
      alias_command :rl, :run_local

      command :clean do |c|
        c.syntax = "pfab clean"
        c.summary = "clean up pods"
        c.description = "clean up old pods"
        c.example "clean up",
                  "pfab clean"
        c.action do |_args, options|
          set_kube_context
          puts "THIS APPLIES TO THE ENTIRE NAMESPACE"
          types = %w(Failed Pending Succeeded)
          types.each do |type|
            kubectl("get pods --field-selector status.phase=#{type}")
            if agree("Delete those?")
              kubectl("delete pods --field-selector status.phase=#{type}")
              puts "Deleted"
            end
          end
        end
      end
      alias_command :rl, :run_local

      default_command :help

      run!
    end

    def cmd_apply(timeout: 240, retries: 3, sleep_duration: 5, tagged: nil)
      set_kube_context
      success = true

      apps = tagged ? deployables.select { |k, v| v[:tags]&.include?(tagged) }.keys : get_apps

      apps.each do |app_name|
        app = deployables[app_name]
        if app[:deployable_type] == "cron"
          deployed_name = deployed_name(app)
          success &= kubectl("delete cronjob -l deployed-name=#{deployed_name}")
        end
        success &= kubectl("apply -f #{FILES_DIR}/.application-k8s-#{$env}-#{app_name}.yaml")
        success &= puts_and_system("git tag release-#{$env}-#{app_name}-#{Time.now.strftime("%Y-%m-%d-%H-%M-%S")} HEAD")
        success &= puts_and_system("git push origin --tags")
      end

      success &= wait_for_deployments_rollout(timeout, retries: retries, sleep_duration: sleep_duration)

      exit(success ? 0 : 1)
    end

    def wait_for_deployments_rollout(timeout, retries: 3, sleep_duration: 5)
      selector = "application=#{@application_yaml['name']}"
      deployment_json = `kubectl get deployment -l #{selector} -o json --namespace=#{yy.namespace}`
      deployments = JSON.parse(deployment_json)

      if deployments["items"].any?
        deployments["items"].each do |deployment|
          deployment_name = deployment["metadata"]["name"]
          puts "Waiting for deployment #{deployment_name} to roll out..."

          rollout_success = false

          retries.times do |attempt|
            rollout_result = kubectl_with_output("rollout status deployment/#{deployment_name} --timeout=#{timeout}s")
            rollout_success = rollout_result.success?
            if rollout_success
              puts "Deployment #{deployment_name} successfully rolled out. Attempt #{attempt + 1}/#{retries}."
              break
            else
              puts "Attempt #{attempt + 1}/#{retries}: Deployment #{deployment_name} failed to roll out within the specified timeout."
              puts "Output was #{rollout_result}"
              if attempt < retries - 1
                puts "Retrying in #{sleep_duration} seconds..."
                sleep(sleep_duration)
              end
            end
          end

          unless rollout_success
            puts "Deployment #{deployment_name} failed to roll out after #{retries} attempts."
            return false
          end
        end
        puts "All deployments successfully rolled out."
        true
      else
        puts "No deployments found for selector: #{selector}"
        false
      end
    end

    def image_exists?(full_image_name)

      # return 0 if image exists 1 if not
      cmd = "docker manifest inspect #{full_image_name} > /dev/null ; echo $?"
      say "Looking for images with #{cmd}"
      existing = `#{cmd}`.strip
      existing == "0"
    end

    def cmd_build(force: false, checkonly: false)
      rev = get_current_sha
      say "This repo is at rev: #{rev}"
      uncommitted_changes = !`git diff-index HEAD --`.empty?
      if uncommitted_changes
        say "FYI! There are uncommitted changes."
        continue = agree("Continue anyway?")
        if continue
          say "carrying on and pushing local code to #{rev}"
        else
          return false
        end
      end

      full_image_name = "#{container_repository}/#{image_name}:#{rev}"

      unless force
        if image_exists?(full_image_name)
          say "Found image #{full_image_name} already, skipping prebuild, build & push"
          return true
        else
          say "No image #{full_image_name} present"
        end
        return if checkonly
      end

      say "No image #{full_image_name} present, building"

      prebuild = @application_yaml["prebuild"] || ""
      if prebuild.empty?
        say "No prebuild task"
      else
        say "Prebuild, running system(#{prebuild})"
        result = system(prebuild)
        if result
          say 'Pfab prebuild success'
        else
          say "Pfab prebuild did not return success. Exiting"
          return false
        end
      end

      build_cmd = "docker buildx build --tag #{image_name} --platform linux/amd64 #{build_args} ."
      puts build_cmd
      result = system(build_cmd)

      puts "Build Result #{result}"

      if result
        puts_and_system "docker tag #{image_name}:latest #{image_name}:#{rev}"
        puts_and_system "docker tag #{image_name}:#{rev} #{full_image_name}"

        puts_and_system "docker push #{container_repository}/#{image_name}:#{rev}"
        return true
      else
        say "Build Did Not Succeed"
        return false
      end

    end

    def yy
      Pfab::Yamls.new(apps: all_runnables,
                      application_yaml: @application_yaml,
                      application_yaml_hash: @application_yaml_hash,
                      env: $env,
                      sha: get_current_sha,
                      image_name: image_name,
                      config: config
      )
    end

    def cmd_generate_yaml
      wrote = yy.generate(deployables.keys)
      puts "Generated #{wrote}"
    end

    def deployed_name(app)
      [app[:application], app[:deployable_type], app[:deployable]].join("-")
    end

    def get_current_sha
      `git rev-parse --short=8 --verify HEAD`.chomp
    end

    def set_kube_context
      str = "kubectl config use-context #{config["envs"][$env.to_s]["context"]}"
      puts_and_system str
    end

    def image_name
      @application_yaml["name"]
    end

    def build_args
      args = @application_yaml["build_args"] || []
      if args.any?
        return args.map{|a| "--build-arg #{a}=$#{a}"}.join(" ")
      end
      ""
    end

    def container_repository
      @_container_repository ||= config["container.repository"]
    end

    def config
      @_config ||= YAML.load(File.read(File.join(Dir.home, ".pfab.yaml")))
    end

    def kubectl(cmd, post_cmd = "")
      result = puts_and_system("kubectl #{cmd} --namespace=#{yy.namespace} #{post_cmd}")
      result == true
    end

    def kubectl_with_output(cmd, post_cmd = "")
      puts_and_system_with_output("kubectl #{cmd} --namespace=#{yy.namespace} #{post_cmd}")
    end

    def puts_and_system(cmd)
      puts cmd
      if $dryrun
        puts "dry run, didn't run that"
        true
      else
        system(cmd)
      end
    end

    def puts_and_system_with_output(cmd)
      puts cmd
      if $dryrun
        dryrun_message = "dry run, didn't run that"
        puts dryrun_message
        CommandResult.new(stdout: dryrun_message, stderr: dryrun_message, exit_status_code: 0)
      else
        stdout, stderr, status = Open3.capture3(cmd)
        CommandResult.new(stdout: stdout, stderr: stderr, exit_status_code: status.exitstatus)
      end
    end

    def deployables
      @_deployables ||= calculate_runnables("deployables")
    end

    def run_locals
      @_rl ||= calculate_runnables("run_locals")
    end

    def all_runnables
      deployables.merge(run_locals)
    end

    def calculate_runnables(runnable_type)
      application = @application_yaml["name"]
      apps = {}
      (@application_yaml[runnable_type] || []).each do |deployable, dep|
        deployable_type = dep["type"]
        app_name = [application, deployable_type, deployable].join("-")
        apps[app_name] = {
          application: application,
          deployable: deployable,
          deployable_type: deployable_type,
          tags: dep["tags"],
          command: dep["command"],
        }
      end
      apps
    end

    def get_first_pod(app)
      if get_pods(app)["items"].empty?
        raise "There are no running pods for #{app}"
      end
      get_pods(app)["items"][0]["metadata"]["name"]
    end

    def get_pods(app)
      get_pods_str = "kubectl get pods -o json -l deployed-name=#{app} --namespace=#{yy.namespace}"
      pods_str = `#{get_pods_str}`
      JSON.parse(pods_str)
    end

    def get_app_name(all: false, include_run_locals: false)
      return $app_name unless $app_name.nil?
      apps = []
      apps << "all" if all
      apps.concat(deployables.keys)
      apps.concat(run_locals.keys) if include_run_locals
      $app_name = choose("which app?", *apps)
    end

    def get_apps
      name = get_app_name(all: true)
      (name == "all") ? deployables.keys : [name]
    end
  end

  CommandResult = Struct.new(:stdout, :stderr, :exit_status_code, keyword_init: true) do
    def success?
      exit_status_code == 0
    end

    def to_s
      "status: #{exit_status_code}\n\nstdout: #{stdout}\n\nstderr: #{stderr}\n\n"
    end
  end
end
