#!/usr/bin/env ruby

require_relative 'harness.rb'

Harness.run_test do
  scenario 'Run single test in continuous mode, fail after several loops'
  log_cmd './baseline -c tests/nested/double-nested/fail_after_5.rb'
end
