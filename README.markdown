pfab
===================

The missing kubernetes deployer / utility

## Why?
pfab's goal is to let you write a clear, concise `application.yaml` and then "just work". 
If you have a kubernetes cluster, a functioning local application and CI, you should be able to create your first deployment done
in 5 minutes.

pfab is designed to support strong opinions, but you're free to have whatever opinion you like by having your own deployable types.

This is what we use to deploy [Prefab](https://prefab.cloud/). 

## Example

This is an example of a simple application.yaml that we hope is self explanatory.

```yaml
# application.yaml
name: myapp

deployables:
  dbmigrate:
    type: job
    command: bundle exec rake db:migrate
  upsert-usage-logs:
    type: cron
    schedule: 2 6 * * *
    command: bundle exec rake upsert-logs
  application:
    type: web
    command: bundle exec rails server
    staging:
      host: api.staginghost.com
      replicas: 1
    production:
      host: api.host.com
      replicas: 2
      
staging:
  environment:
    RAILS_ENV: "staging"
production:
  environment:
    RAILS_ENV: "production"
```
Given an `application.yaml` like this we can run:
```bash
~/Documents/workspace/myapp (main)  $ pfab shipit
# Check image repository for an image or build and push one
# Generate kubernetes yaml
# Apply kubernetes yaml

# Now we can quickly check the status
~/Documents/workspace/myapp (main)  $ pfab status
kubectl config use-context staging
Switched to context "staging".
kubectl get ingresses,jobs,services,cronjobs,deployments,pods -l application=myapp --namespace=myapp 
NAME                                                    CLASS    HOSTS                  ADDRESS   PORTS     AGE
ingress.networking.k8s.io/ingress-myapp-web-web   <none>   api.staginghost.com             80, 443   224d

NAME                                               COMPLETIONS   DURATION   AGE
job.batch/job-myapp-job-dbmigrate-7854c854   1/1           3m34s      205d

NAME                          TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
service/myapp-web-web   ClusterIP   10.1.1.1    <none>        80/TCP    224d

NAME                                                             SCHEDULE    SUSPEND   ACTIVE   LAST SCHEDULE   AGE
cronjob.batch/myapp-cron-upsert-usage-logs-92d90b8e   2 6 * * *   False     0        <none>          62m

NAME                                  READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/myapp-web-web   1/1     1            1           224d

NAME                                       READY   STATUS    RESTARTS   AGE
pod/myapp-web-web-8678649967-fqfgb   1/1     Running   0          42h

# or tail the logs
~/Documents/workspace/myapp (master)  $ pfab logs
kubectl config use-context prefab-cloud-staging
Switched to context "prefab-cloud-staging".
which app?
1. myapp-job-dbmigrate
2. myapp-web-web
3. myapp-cron-upsert-usage-logs
?  2
kubectl logs -f myapp-web-web-8678649967-fqfgb --namespace=myapp 
=> Booting Puma
=> Rails 5.1.7 application starting in staging 
...

# or exec into a pod
~/Documents/workspace/myapp (master)  $ pfab exec
kubectl config use-context staging
Switched to context "staging".
which app?
1. myapp-web-web
?  1
kubectl exec -it myapp-web-web-8678649967-fqfgb --namespace=myapp -- /bin/sh
# _

```

## Deployable Types
pfab supports `web`, `job`, `cron`, and `daemon` deployables. Each deployable type is just a ruby file that outputs json. To add your own you could simply create / modify the `web.rb`. Best practice is to put as much messy, boiler plate as possible into the templates and keep the `application.yaml` as clean as possible. An example of a deployable is [cron.rb](https://github.com/prefab-cloud/pfab/blob/main/lib/pfab/templates/cron.rb).


## What it Does
```
  COMMANDS:
        
    apply         kubectl apply         
    build         build image           
    clean         clean up pods         
    exec          kubectl exec into a pod              
    generate_yaml build k8s yaml from application.yaml    
    logs          tail logs             
    restart       rolling restart of a deployment                       
    run_local     run an app locally            
    shipit        build, generate, apply                
    status        status of an app      
```

## Project Status
This is very much an internal tool today. It would be worth having a conversation before using it yourself. You may want to just fork it and have it your way.

## Setup

Configure ~/.pfab.yaml
```
container.repository: "gcr.io/$$$$$$$"
default_cpu_string: "50m/250m"
default_memory_string: "256Mi/500Mi"
envs: 
  staging:
    context: "k8s-staging-context"
  production:
    context: "k8s-production-context"
```

# application.yaml
Supported Features (see examples below)
- Env Vars & env specific env vars
- Secrets from k8s secrets
- Config Maps & env_from
- Custom probes
- cpu/memory limits
- TLS certs
- GRPC / h2c

```$yaml
name: myapp
prebuild: "mvn -T 4 clean package"

deployables:
  kafkaconsumer:
    type: daemon
    command: java  -Xmx550m -javaagent:/app/dd-java-agent.jar -jar myjar.jar kafkarunner
    cpu: 50m/250m
    memory: 400Mi/600Mi
  dbmigrate:
    type: job
    command: java -jar myjar.jar db_migrate
  upsert-usage-logs:
    type: cron
    schedule: 2 6 * * *
    command: java -jar myjar.jar my_nightly_job
  grpc:
    type: web
    port: 8443
    protocol: h2c # tell traefik this is going to be http2
    tls_cert_secret: my-tls-secret
    command: java -Xmx550m -javaagent:/app/dd-java-agent.jar -jar myjar.jar server /app/grpc.yml
    readinessProbe:
      exec:
        command: ["/bin/grpc_health_probe", "-addr=:8443"]
      initialDelaySeconds: 5
    livenessProbe:
      exec:
        command: ["/bin/grpc_health_probe", "-addr=:8443"]
      initialDelaySeconds: 120
    staging:
      host: api.staginghost.com
      replicas: 1
    production:
      host: api.host.com
      replicas: 2
    cpu: 50m/250m
    memory: 600Mi/768Mi


env_from:
    - configMapRef:
        name: my_config_map
    - secretRef:
        name: my_secrets

staging:
  environment:
    ENV_VAR_URL: "staging.example.com"
production:
  environment:
    ENV_VAR_URL: "example.com"
env_secrets:
  AWS_SECRET_ACCESS_KEY: secretstore/aws_secret_access_key
environment:
  DD_AGENT_HOST: field/status.hostIP
  AWS_ACCESS_KEY_ID: "1234"
```


Contributing to pfab
------------------------------------------

-   Check out the latest master to make sure the feature hasn't been
    implemented or the bug hasn't been fixed yet.
-   Check out the issue tracker to make sure someone already hasn't
    requested it and/or contributed it.
-   Fork the project.
-   Start a feature/bugfix branch.
-   Commit and push until you are happy with your contribution.
-   Make sure to add tests for it. This is important so I don't break it
    in a future version unintentionally.
-   Please try not to mess with the Rakefile, version, or history. If
    you want to have your own version, or is otherwise necessary, that
    is fine, but please isolate to its own commit so I can cherry-pick
    around it.

Local Testing
-----------------------------------------
```bash
bundle exec rake clean build
gem install --local pkg/pfab-0.57.1.gem
```
```ruby
gem 'pfab', :path => "../pfab"
```

Releasing
-----------------------------------------

- modify version.rb
- ```bundle exec rake gemspec```
- ```git commit ```
- ```REMOTE_BRANCH=main LOCAL_BRANCH=main bundle exec rake git:release```
- ```REMOTE_BRANCH=main LOCAL_BRANCH=main bundle exec rake clean build```
- ```gem push pkg/pfab-0.45.0.gem```

Copyright
---------

Copyright (c) 2025 Prefab Inc. See
LICENSE.txt for further details.
