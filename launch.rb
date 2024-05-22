#!/usr/bin/env ruby
# this file can be used to run CLI locally for debugging etc
$LOAD_PATH.unshift File.expand_path('../lib', __FILE__)
require "pfab"

Pfab::CLI.new.run
