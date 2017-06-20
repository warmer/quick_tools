#!/usr/bin/env ruby

require_relative 'harness.rb'

Harness.run_test do
  scenario 'Update a directory'
  log_cmd '-b tests'
end
