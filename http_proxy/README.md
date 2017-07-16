# reverse_http_proxy.rb

`reverse_http_proxy.rb` is a tool that can assist with development, testing,
and scraping of websites by providing a way to capture, inspect, and modify
all requests to a website made by a real browser or HTTP client.

The proxy is configured to listen for HTTP requests on a port, then forward
those requests to a remote host. The proxy will change outgoing host headers
to match that of the configured remote host, but in its default behavior,
otherwise leaves requests unmodified.

The proxy can also be configured with a simple read-only cache or with cache
writeback.

```
+---------+ -- request ---> +-------+ -- request ---> +--------+
| browser |                 | proxy |                 | remote |
+---------+ <-- response -- +-------+ <-- response -- +--------+
```

Because this is a reverse proxy, not a forward proxy, only HTTP requests
made directly to the proxy are affected by proxy behavior.

## Dependencies

`reverse_http_proxy.rb` requires Ruby 1.9 or greater and requires no gems.

A [baseline](../baseline/) test tool is needed to run the tests in
[regress](./regress/), but this script is otherwise self-contained in a
single file to maximize portability and utility.

## Usage

Run the proxy directly from the command line:

```
Usage: ./reverse_http_proxy.rb [options]
    -h, --remote-host=HOST           Remote Host
    -p, --remote-port=PORT           Remote Port
        --listen-host=HOST           Listen Host
        --listen-port=PORT           Proxy Port
    -w, --write-cache                Write remote host responses to cache (use with "-d")
    -d, --cache-dir=PATH             Directory to use for local cache of requests
    -?, --help                       Display help
```

## Use cases

### Development

This proxy can assist with web development by selectively allowing local
content to be served alongside remote content. One use case for this is
developing a new look and feel or front-end (HTML/JavaScript) with some
locally-edited content and some remotely-fetched content.

For example, let's say you have a website being hosted on example.com that
contains these resources:

```
/index.html
/custom.css
/custom.js
```

If you wanted to see how `http://example.com/index.html` looked with a new
`custom.css`, you could:

1. Download `http://example.com/custom.css` into a local cache directory
2. Make edits to `custom.css` in that cache directory
3. Use `reverse_http_proxy.rb` to serve cached content from that cache
  directory while otherwise forwarding your requests to example.com:
  `./reverse_http_proxy.rb --remote-host example.com --cache-dir cache/ --listen-port 9876`
4. Visit http://localhost:9876/index.html to see how your changes look

### Testing

This proxy is well-documented and breaks headers, requests, and responses into
pieces, making it easy to modify request and response behavior for testing.

For example, if you wanted to add, remove, or modify headers sent to either
the remote host or the client receiving the response, you could override
`ReverseHttpProxy::Client.send_headers` with your own functionality.

### Manual Page Scraping

The proxy can also be configured to write content back locally. This could
be used to manually scrape content from a website.
