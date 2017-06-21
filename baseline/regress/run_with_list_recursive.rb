#!/usr/bin/env ruby

require_relative 'harness.rb'

Harness.run_test do
  scenario 'Run with a list of files/directories, recursive'
  log_cmd './baseline.rb -r tests/*'
end
