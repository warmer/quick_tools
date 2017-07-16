#!/usr/bin/env ruby

require_relative 'harness.rb'

Harness.run_test do
  scenario 'Request files that exist in "serve" through both endpoints'
  serve_files.each do |file|
    log_response(origin_get("/#{file}"))
    log_response(proxy_get("/#{file}"))
    log '+' * 80
  end
  log

  scenario 'Request files that exist in "cache" through both endpoints'
  cache_files.each do |file|
    log_response(origin_get("/#{file}"))
    log_response(proxy_get("/#{file}"))
    log '+' * 80
  end
  log

  log 'Remote access log:'
  log @remote_log.string
  log

  log 'Proxy log:'
  log @proxy_log.string
  log
end
