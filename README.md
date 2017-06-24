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

# Configuration Files

[.vimrc](./.vimrc) - An example `.vimrc` file used for personal development

[.gitignore_global](./.gitignore_global) - My global `.gitignore` file. Drop
into your home directory and add to your global git settings with:
`git config --global core.excludesfile ~/.gitignore_global`
This is a good way to add editor-specific temp files that don't belong in
individual projects (so you don't have to fill every project's `.gitignore`
file with every possible editor's temporary files).
