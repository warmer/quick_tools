# Overview

Collection of lightweight, quick and clean tools, configuration, etc that
might otherwise make good gists.

Emphasis is on simplicity: few dependencies, easy-to-read, canonical
examples.

# Contents

`./simple_aws.rb` - provides mechanism for signing HTTP requests to
AWS without needing the `aws-sdk` gem. Designed for copy/paste to be
embedded directly. Examples for several common `S3` operations included.

`./xkcd_pw.rb` - Inspired by https://xkcd.com/936/ - generates a passphrase
using N (default=4) random, common English words.

[vms/](./vms/)` - Useful scripts and notes for working with QEMU VMs,
especially if you want to enable PCI passthrough.
