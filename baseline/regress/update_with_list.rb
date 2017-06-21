#!/usr/bin/env ruby

require_relative 'harness.rb'

Harness.run_test do
  scenario 'Update list of files/directories'
  log_cmd './baseline -b tests/*'
end
