#!/usr/bin/env ruby

require_relative 'harness.rb'

Harness.run_test do
  scenario 'Test before the update'
  log_cmd './baseline tests'

  scenario 'Update a directory'
  log_cmd './baseline -b tests'

  scenario 'Test after the first update'
  log_cmd './baseline tests'

  scenario 'Re-run update'
  log_cmd './baseline -b tests'

  scenario 'Test after the second update'
  log_cmd './baseline tests'
end
