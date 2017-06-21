#!/usr/bin/env ruby

require_relative 'harness.rb'

Harness.run_test do
  scenario 'Run quietly (includes failures)'
  log_cmd './baseline -q tests'

  scenario 'Run quietly (single passing test)'
  log_cmd './baseline -q tests/up_to_date.rb'

  scenario 'Run quietly (single failing test)'
  log_cmd './baseline -q tests/baselined_out_of_date.rb'

  scenario 'Run quietly (no executable test)'
  log_cmd './baseline -q tests/non_executable.rb'
end
