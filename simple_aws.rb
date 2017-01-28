require 'time'
require 'openssl'
require 'net/http'

# Pure-ruby implementation of common AWS HTTP requests
# Note that OpenSSL must be installed on the system
# Works for Ruby >= 2.0 (minor differences in Net::HTTP::Get etc arguments
# prevent this from working in Ruby 1.9.x)
module SimpleAws
  # Usage:
  # s3 = SimpleAws::S3.new('example-bucket')
  # s3.put('example.txt', 'this is an example')
  # s3.get('example.txt') => 'this is an example'
  # s3.list('ex') => {
  #   [{key: 'example.txt', ...}, ...]
  class S3
    def initialize(bucket, opts = {})
      @bucket = bucket
      opts[:service] = 's3'
      @sig = AwsSigV4.new(opts)
    end

    def get(key)
      path = File.join('/', key)
      uri = URI.parse("http://#{@bucket}.s3.amazonaws.com#{path}")
      req = Net::HTTP::Get.new(uri)
      @sig.signed_headers(:get, uri, {}).each {|k, v| req[k] = v}
      res = Net::HTTP.start(uri.hostname, uri.port) {|http| http.request(req)}
      raise "Invalid response from AWS: #{res.code}" unless res.code.to_s == '200'
      res.body
    end

    def put(key, content)
      path = File.join('/', key)
      uri = URI.parse("http://#{@bucket}.s3.amazonaws.com#{path}")
      req = Net::HTTP::Put.new(uri)
      req.body = content
      headers = {'Content-Type' => 'binary/octet-stream'}
      @sig.signed_headers(:put, uri, headers, content).each {|k, v| req[k] = v}
      res = Net::HTTP.start(uri.hostname, uri.port) {|http| http.request(req)}
      raise "Invalid response from AWS: #{res.code}" unless res.code.to_s == '200'
      puts res.inspect
      res.body
    end

    def list(prefix)
      prefix = prefix[1..-1] if prefix[0] == '/'
      uri = URI.parse("http://#{@bucket}.s3.amazonaws.com/?list-type=2&prefix=#{prefix}")
      req = Net::HTTP::Get.new(uri)
      @sig.signed_headers(:get, uri, {}).each {|k, v| req[k] = v}
      res = Net::HTTP.start(uri.hostname, uri.port) {|http| http.request(req)}
      raise "Invalid response from AWS: #{res.code}" unless res.code.to_s == '200'
      contents = res.body
      contents = contents.gsub(/<Contents>/, "\n<Contents>").split("\n")
      contents = contents.select{|cl| cl =~ /^<Contents>/}
      contents.map do |cl|
        { key: (/<Key>(.*)<\/Key>/ =~ cl) ? $1 : nil,
          last_modified: (/<LastModified>(.*)<\/LastModified>/ =~ cl) ? $1 : nil,
          etag: (/<ETag>(.*)<\/ETag>/ =~ cl) ? $1.gsub(/&quot;/,'') : nil,
          size: (/<Size>(.*)<\/Size>/ =~ cl) ? $1 : nil,
          storage_class: (/<StorageClass>(.*)<\/StorageClass>/ =~ cl) ? $1 : nil,
        }
      end
    end
  end

  class AwsSigV4
    def initialize(opts = {})
      @service = opts[:service]
      @region = opts[:region] || 'us-east-1'
      @key_id = opts[:key_id] || ENV[:AWS_ACCESS_KEY_ID]
      @secret = opts[:secret] || ENV[:AWS_SECRET_ACCESS_KEY]
      raise 'Must provide :service' unless @service
      raise 'Must provide :key_id or set ENV[AWS_ACCESS_KEY_ID]' unless @key_id
      raise 'Must provide :secret or set ENV[AWS_SECRET_ACCESS_KEY]' unless @secret
    end

    def signed_headers(method, url, headers, payload = '')
      can_req = canonical_request(method, url, headers, payload)
      puts "#{'#'*40}\n#{can_req}\n#{'='*40}"
      str_to_sign = string_to_sign(can_req, headers['x-amz-date'])
      puts "#{'='*40}\n#{str_to_sign}\n#{'='*40}"
      short_date = headers['x-amz-date'].split('T')[0]
      key = signing_key(short_date)
      sig = OpenSSL::HMAC.hexdigest('sha256', key, str_to_sign)
      signed_headers = headers.keys.map{|h| h.downcase}.sort.join(';')
      auth_str = auth_string(signed_headers, short_date, sig)
      headers['Authorization'] = auth_str
      headers
    end

    private

    def canonical_request(method, uri, headers, payload = '')
      uri = URI.parse(uri) unless uri.is_a? URI
      can_uri = "#{uri.path.empty? ? '/' : uri.path}"
      can_query = URI.encode(uri.query || '')

      # add content sha to the headers
      payload_hash = Digest::SHA256.hexdigest(payload)
      headers['x-amz-content-sha256'] = payload_hash
      headers['Host'] = uri.host

      # add the date to the headers
      request_time = Time.now
      headers['Date'] ||= request_time.httpdate
      headers['x-amz-date'] ||= request_time.utc.strftime("%Y%m%dT%H%M%SZ")

      can_headers = canonical_headers(headers)
      signed_headers = headers.keys.map{|h| h.downcase}
      signed_headers = signed_headers.sort.join(';')

      [ method.to_s.upcase,
        can_uri,
        can_query,
        can_headers,
        signed_headers,
        payload_hash
      ].join("\n")
    end

    def string_to_sign(canonical_request, date)
      [ 'AWS4-HMAC-SHA256',
        date,
        "#{date.split('T')[0]}/#{@region}/#{@service}/aws4_request",
        Digest::SHA256.hexdigest(canonical_request)
      ].join("\n")
    end

    def signing_key(date)
      key = OpenSSL::HMAC.digest('sha256', "AWS4#{@secret}", date)
      key = OpenSSL::HMAC.digest('sha256', key, @region)
      key = OpenSSL::HMAC.digest('sha256', key, @service)
      OpenSSL::HMAC.digest('sha256', key, 'aws4_request')
    end

    def auth_string(signed_headers, short_date, signature)
      pieces = [
        "Credential=#{@key_id}/#{short_date}/#{@region}/#{@service}/aws4_request",
        "SignedHeaders=#{signed_headers}",
        "Signature=#{signature}"
      ]
      "AWS4-HMAC-SHA256 #{pieces.join(',')}"
    end

    def canonical_headers(headers)
      can_hdr = headers.keys.map {|h| "#{h.downcase}:#{headers[h].strip}"}.sort
      can_hdr.join("\n") + "\n"
    end
  end
end
