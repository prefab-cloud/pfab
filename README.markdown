pfab
===================

The missing k8s deployer


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


staging:
  environment:
    ENV: staging
production:
  environment:
    ENV: production
env_secrets:
  AWS_SECRET_ACCESS_KEY: secretstore/aws_secret_access_key
environment:
  DD_AGENT_HOST: field/status.hostIP
  AWS_ACCESS_KEY_ID: "1234"
```



# Profit
```
pfab shipit
pfab status
pfab logs
pfab exec
pfab run_local
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

Copyright
---------

Copyright (c) 2018 Jeff Dwyer. See
LICENSE.txt for further details.
