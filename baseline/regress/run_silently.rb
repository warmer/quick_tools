#!/usr/bin/env ruby

require_relative 'harness.rb'

Harness.run_test do
  scenario 'Run silently (includes failures)'
  log_cmd './baseline -s tests'

  scenario 'Run silently (single passing test)'
  log_cmd './baseline -s tests/up_to_date.rb'

  scenario 'Run silently (single failing test)'
  log_cmd './baseline -s tests/baselined_out_of_date.rb'

  scenario 'Run silently (no executable test)'
  log_cmd './baseline -s tests/non_executable.rb'
end
