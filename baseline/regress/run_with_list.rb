#!/usr/bin/env ruby

require_relative 'harness.rb'

Harness.run_test do
  scenario 'Run with a list of files/directories'
  log_cmd './baseline tests/*'
end
