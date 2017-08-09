#!/usr/bin/env ruby

require_relative 'harness.rb'

Harness.run_test do
  scenario 'Run directory in continuous mode, fail after several loops'
  log_cmd './baseline -c tests/nested/double-nested/'
end
