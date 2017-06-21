#!/usr/bin/env ruby

require_relative 'harness.rb'

Harness.run_test do
  scenario 'Print the help for baseline'
  log_cmd './baseline --help'

  scenario 'Run baseline with an invalid argument'
  log_cmd './baseline -m'

  scenario 'Run baseline with no arguments'
  log_cmd './baseline'
end
