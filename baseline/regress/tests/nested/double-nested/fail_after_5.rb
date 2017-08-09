#!/usr/bin/env ruby

# write a file to our current running location that we will use to introduce
# deliberate non-determinism to this test

file_to_update = File.join(File.dirname(__FILE__), 'file_to_update.txt')
File.write(file_to_update, "0") unless File.exist?(file_to_update)

counter = File.read(file_to_update).to_i
puts 'Time to be different' if counter > 4

puts 'Up to date!'

File.write(file_to_update, (counter + 1).to_s)
