require "commander"
require "net/http"
require "yaml"
require "json"
require 'active_support/core_ext/hash/indifferent_access'

module Pfab
  class CLI
    include Commander::Methods

    def run
      program :name, "pfab"
      program :version, "0.0.0"
      program :description, "k8s helper"

      if File.exist? "application.yaml"
        @application_yaml = YAML.load(File.read("application.yaml")).with_indifferent_access
      else
        raise "I need to be run in a directory with a application.yaml"
      end

      global_option("--verbose") { $verbose = true }
      $env = :staging
      global_option("-p") { $env = :production }
      global_option("-a", "--application_name APP_NAME", "run without prompting for app") do |app_name|
        $app_name = app_name
      end

      @apps = apps

      command :build do |c|
        c.syntax = "pfab build"
        c.summary = "build image"
        c.option "--force", "force build and push"
        c.action do |_args, options|
          cmd_build(force: options.force)
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
        c.action do
          cmd_build
          cmd_generate_yaml
          cmd_apply
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

          puts_and_system("kubectl logs -f #{first_pod}")
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
            puts_and_system "kubectl get pods -l #{selector} -w"
          elsif $verbose
            puts_and_system "kubectl describe pods -l #{selector}"
          else
            puts_and_system "kubectl get ingresses,jobs,services,cronjobs,deployments,pods --include-uninitialized=true -l #{selector}"
          end
        end
      end

      default_command :help

      run!
    end

    def cmd_apply
      set_kube_context
      app_name = get_app_name
      puts_and_system("kubectl apply -f .application-k8s-#{$env}-#{app_name}.yaml")
    end

    def cmd_build(force: false)

      rev = get_current_sha
      say "This repo is at rev: #{rev}"

      full_image_name = "#{container_repository}/#{image_name}:#{rev}"

      cmd = "docker images -q #{full_image_name}"
      say "Looking for images with #{cmd}"
      existing = `#{cmd}`

      if !existing.to_s.empty? && !force
        say "Found image #{full_image_name} already, skipping build & push"
        return
      end

      say "No image #{full_image_name} present, building"

      puts_and_system "docker build -t #{image_name} ."

      puts_and_system "docker tag #{image_name}:latest #{image_name}:#{rev}"
      puts_and_system "docker tag #{image_name}:#{rev} #{full_image_name}"

      puts_and_system "docker push #{container_repository}/#{image_name}:#{rev}"

    end

    def cmd_generate_yaml
      wrote = Pfab::Yamls.generate_for(apps: @apps,
                                       application_yaml: @application_yaml,
                                       env: $env,
                                       sha: get_current_sha,
                                       image_name: image_name,
                                       container_repository: container_repository
      )
      puts "Generated #{wrote}"
    end

    def get_current_sha
      `git rev-parse --short --verify HEAD`.chomp
    end

    def set_kube_context
      str = "kubectl config use-context #{config["envs"][$env.to_s]["context"]}"
      puts_and_system str
    end

    def image_name
      @application_yaml["name"]
    end

    def container_repository
      @_container_repository ||= @config["container.repository"]
    end

    def config
      @config ||= YAML.load(File.read(File.join(Dir.home, ".pfab.yaml")))
    end

    def puts_and_system cmd
      puts cmd
      system cmd
    end

    def apps
      @_apps ||= calculate_apps
    end

    def calculate_apps
      application = @application_yaml["name"]
      apps = {}
      @application_yaml["deployables"].each do |deployable, dep|
        deployable_type = dep["type"]
        app_name = [application, deployable_type, deployable].join("-")
        apps[app_name] = {
          application: application,
          deployable: deployable,
          deployable_type: deployable_type,
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
      get_pods_str = "kubectl get pods -o json -l deployed-name=#{app}"
      puts get_pods_str
      pods_str = `#{get_pods_str}`
      JSON.parse(pods_str)
    end

    def get_app_name
      return $app_name unless $app_name.nil?
      choose("which app?", *@apps.keys)
    end
  end
end
