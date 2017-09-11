# Overview

Collection of lightweight, quick and clean tools, configuration, etc that
might otherwise make good gists.

Emphasis is on simplicity: few dependencies, easy-to-read, canonical
examples.

# Contents

[simple_aws.rb](./simple_aws.rb) - provides mechanism for signing HTTP requests
to AWS without needing the `aws-sdk` gem. Designed for copy/paste to be
embedded directly. Examples for several common `S3` operations included.

[xkcd_pw.rb](./xkcd_pw.rb) - Inspired by https://xkcd.com/936/ - generates a
passphrase using N (default=4) random, common English words.

[vms/](./vms/) - Useful scripts and notes for working with QEMU VMs,
especially if you want to enable PCI passthrough.

[baseline](./baseline/) - A well-tested and well-documented single-script,
dependency-free baseline testing tool.

[javascript](./javascript/) - Quick references for several JavaScript actions,
usage patterns, and library usage.

[http_client.rb](./http_client.rb) - Minimal, portable, pure-Ruby HTTP client
for core HTTP actions.

Usage example:
```ruby
require 'http_client.rb'
client = HttpClient.new('http://localhost:9292')

# simple GET
response = client.get('/')

# simple POST
headers = {'Content-Type' => 'application/x-www-form-urlencoded'}
body = URI.encode_www_form('key' => 'value')
response = client.post('/dest', headers, body)

# simple PUT
headers = {'Content-Type' => 'application/json'}
body = '{"key":"value"}'
response = client.put('/dest', headers, body)

# simple DELETE
response = client.delete('/dest')

# All supported HTTP actions return a Net::HTTP object that has detailed
# information about the response. Examples include:
# response content: response.body
# response HTTP code: response.code
# response status message: response.message
# response headers: response.each { |header_name, values| ... }
```

# One/Few-line Utilities

## HTTP Servers

These serve files over HTTP from the current directory. In these examples,
replace `8080` with the desired port to serve on a different port.

Python:
```
python -m SimpleHTTPServer 8080
```

Ruby:
```
ruby -e "require 'webrick'; WEBrick::HTTPServer.new(DocumentRoot: '.', BindAddress: '127.0.0.1', Port: 8080).start"
```

## Match pairing

Given an even number `N` of players, create `N - 1` rounds where every
player has exactly one match against every other player.

```ruby
def shuffle(a)
  a.insert(a.size / 2, a.delete(a[1]))
  a.insert(a.size / 2, a.pop)
end

def match(players)
  num = players.length
  rounds = Array.new(num - 1)  { |index| Array.new() }

  (num - 1).times do |round|
    (num / 2).times do |pair|
      match = [players[pair], players[pair + (num/2)]]
      rounds[round] << [match.min, match.max]
    end

    players = shuffle(players)
  end
  rounds
end
```

Example 1:
```
pry(main)> match (0..7).to_a
=> [[[0, 4], [1, 5], [2, 6], [3, 7]],
 [[0, 7], [1, 2], [3, 5], [4, 6]],
 [[0, 6], [2, 3], [1, 4], [5, 7]],
 [[0, 5], [3, 4], [2, 7], [1, 6]],
 [[0, 1], [4, 7], [3, 6], [2, 5]],
 [[0, 2], [6, 7], [4, 5], [1, 3]],
 [[0, 3], [5, 6], [1, 7], [2, 4]]]
```

Example 2:
```
pry(main)> match ['amy', 'fred', 'anne', 'bob']
=> [[["amy", "anne"], ["bob", "fred"]],
 [["amy", "bob"], ["anne", "fred"]],
 [["amy", "fred"], ["anne", "bob"]]]
```

# Configuration Files

[.vimrc](./.vimrc) - An example `.vimrc` file used for personal development

[.gitignore_global](./.gitignore_global) - My global `.gitignore` file. Drop
into your home directory and add to your global git settings with:
`git config --global core.excludesfile ~/.gitignore_global`
This is a good way to add editor-specific temp files that don't belong in
individual projects (so you don't have to fill every project's `.gitignore`
file with every possible editor's temporary files).
