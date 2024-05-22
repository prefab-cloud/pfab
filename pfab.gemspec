# Generated by juwelier
# DO NOT EDIT THIS FILE DIRECTLY
# Instead, edit Juwelier::Tasks in Rakefile, and run 'rake gemspec'
# -*- encoding: utf-8 -*-
# stub: pfab 0.55.1 ruby lib

Gem::Specification.new do |s|
  s.name = "pfab".freeze
  s.version = "0.55.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Jeff Dwyer".freeze]
  s.date = "2024-05-22"
  s.description = "k8s helper".freeze
  s.email = "jdwyer@prefab.cloud".freeze
  s.executables = ["pfab".freeze]
  s.extra_rdoc_files = [
    "LICENSE.txt",
    "README.markdown"
  ]
  s.files = [
    ".document",
    ".tool-versions",
    "CODEOWNERS",
    "Gemfile",
    "Gemfile.lock",
    "LICENSE.txt",
    "README.markdown",
    "Rakefile",
    "bin/pfab",
    "launch.rb",
    "lib/pfab.rb",
    "lib/pfab/cli.rb",
    "lib/pfab/templates/base.rb",
    "lib/pfab/templates/cron.rb",
    "lib/pfab/templates/daemon.rb",
    "lib/pfab/templates/job.rb",
    "lib/pfab/templates/web.rb",
    "lib/pfab/version.rb",
    "lib/pfab/yamls.rb",
    "pfab.gemspec",
    "test/helper.rb",
    "test/test_pfab.rb"
  ]
  s.homepage = "http://github.com/prefab-cloud/pfab".freeze
  s.licenses = ["MIT".freeze]
  s.rubygems_version = "3.3.7".freeze
  s.summary = "helper gem".freeze

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<commander>.freeze, [">= 0"])
    s.add_runtime_dependency(%q<activesupport>.freeze, [">= 0"])
    s.add_runtime_dependency(%q<pry-byebug>.freeze, [">= 0"])
    s.add_runtime_dependency(%q<styled_yaml>.freeze, ["~> 0.0.1"])
    s.add_development_dependency(%q<rdoc>.freeze, ["~> 6.1"])
    s.add_development_dependency(%q<bundler>.freeze, ["~> 2.3"])
    s.add_development_dependency(%q<juwelier>.freeze, ["~> 2.4.9"])
    s.add_development_dependency(%q<simplecov>.freeze, [">= 0"])
    s.add_development_dependency(%q<test-unit>.freeze, [">= 0"])
  else
    s.add_dependency(%q<commander>.freeze, [">= 0"])
    s.add_dependency(%q<activesupport>.freeze, [">= 0"])
    s.add_dependency(%q<pry-byebug>.freeze, [">= 0"])
    s.add_dependency(%q<styled_yaml>.freeze, ["~> 0.0.1"])
    s.add_dependency(%q<rdoc>.freeze, ["~> 6.1"])
    s.add_dependency(%q<bundler>.freeze, ["~> 2.3"])
    s.add_dependency(%q<juwelier>.freeze, ["~> 2.4.9"])
    s.add_dependency(%q<simplecov>.freeze, [">= 0"])
    s.add_dependency(%q<test-unit>.freeze, [">= 0"])
  end
end

