pfab
===================

nothing to see here


set ~/.pfab.yaml
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

Then
```
pfab shipit
pfab status
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
