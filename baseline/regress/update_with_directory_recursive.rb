#!/usr/bin/env ruby

require_relative 'harness.rb'

Harness.run_test do
  scenario 'Update list of files/directories, recursive'
  log_cmd './baseline.rb -b -r tests'
end
