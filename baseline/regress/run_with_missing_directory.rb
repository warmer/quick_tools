#!/usr/bin/env ruby

require_relative 'harness.rb'

Harness.run_test do
  scenario 'Run with a directory'
  log_cmd './baseline no-tests/'
end
