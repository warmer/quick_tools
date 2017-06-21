#!/usr/bin/env ruby

require_relative 'harness.rb'

Harness.run_test do
  puts 'Changing directories into "tests/"'
  Dir.chdir('tests') do
    scenario 'Run baseline from a different dir against a dir'
    log_cmd '../baseline .'

    scenario 'Run baseline from a different dir against individual files'
    log_cmd '../baseline ./*.rb'

    scenario 'Run baseline against a nested dir from a different dir'
    log_cmd '../baseline nested'
  end
end
