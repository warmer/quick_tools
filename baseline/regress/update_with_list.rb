#!/usr/bin/env ruby

require_relative 'harness.rb'

Harness.run_test do
  scenario 'Update list of files/directories'
  log_cmd '-b tests/*'
end
