#!/usr/bin/env ruby

require_relative 'harness.rb'

Harness.run_test do
  scenario 'Test before the update'
  log_cmd './baseline.rb tests'

  scenario 'Update a directory'
  log_cmd './baseline.rb -b tests'

  scenario 'Test after the first update'
  log_cmd './baseline.rb tests'

  scenario 'Re-run update'
  log_cmd './baseline.rb -b tests'

  scenario 'Test after the second update'
  log_cmd './baseline.rb tests'
end
