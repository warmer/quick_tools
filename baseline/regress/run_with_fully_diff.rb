#!/usr/bin/env ruby

require_relative 'harness.rb'

Harness.run_test do
  scenario 'Run with a full diff'
  log_cmd '-f tests'
end
