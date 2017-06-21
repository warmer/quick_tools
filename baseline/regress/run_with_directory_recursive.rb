#!/usr/bin/env ruby

require_relative 'harness.rb'

Harness.run_test do
  scenario 'Run with a directory, recursive'
  log_cmd './baseline -r tests'
end
