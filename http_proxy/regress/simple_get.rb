#!/usr/bin/env ruby

require_relative 'harness.rb'

Harness.run_test do
  scenario 'Get from origin'
  log_response(origin_get('/content.txt'))

  scenario 'Get from proxy'
  log_response(proxy_get('/content.txt'))

  puts 'Remote access log:'
  puts @remote_log.string
  puts

  puts 'Proxy log:'
  puts @proxy_log.string
  puts
end
