#!/usr/bin/env ruby

require_relative 'harness.rb'

Harness.run_test do
  scenario 'Run list of tests in continuous mode'
  log_cmd './baseline -c tests/*'
end
