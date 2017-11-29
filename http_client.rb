require 'net/http'
require 'net/https'
require 'uri'

# This provides helper methods for common HTTP actions and is based on a
# several implementations of this basic functionality written over the years.
#
# Intended usage: simple HTTP library in a single, portable file, that
# abstracts the basic HTTP functionality found in Ruby's standard library
#
# Usage notes: the client will supply basic auth credentials for all requests
# if initialized with a username and password. The client does NOT support
# more advanced functionality like protocol determination (HTTP vs HTTPS),
# cookie management, etc.
class HttpClient
  def initialize(base_url, username = nil, password = nil)
    @base_url = base_url
    @username = username
    @password = password
  end

  def get(path, headers = {})
    request(Net::HTTP::Get, path, headers)
  end

  def post(path, body = "", headers = {})
    request(Net::HTTP::Post, path, headers, body)
  end

  def put(path, body = "", headers = {})
    request(Net::HTTP::Put, path, headers, body)
  end

  def delete(path, headers = {})
    request(Net::HTTP::Delete, path, headers)
  end

  private

  def request(type, path, headers, body = nil)
    uri = URI.parse("#{@base_url}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    if uri.scheme == 'https'
      http.use_ssl
      # uncomment if connecting to untrusted endpoint
      #http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end
    request = type.new(uri.request_uri)
    request.basic_auth @username, @password unless @username.nil?
    headers.keys.each { |k| request[k] = headers[k] }
    request.body = body if body
    http.request(request)
  end
end
