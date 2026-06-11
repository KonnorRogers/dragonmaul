#!/usr/bin/env ruby
# snake_rename.rb
# Recursively renames files and directories to snake_case:
#   - Spaces become underscores
#   - CamelCase / interior capitals get an underscore prefix, then lowercased
#   - All letters are lowercased

require "find"
require 'fileutils'

def to_snake_case(name, is_dir: false)
  new_name = ""
  if is_dir
    new_name = File.basename(name)
      .gsub(' ', '_')
      .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
      .gsub(/([a-z\d])([A-Z])/, '\1_\2')
      .downcase
  else
    ext  = File.extname(name)
    base = File.basename(name, ext)
    result = base
      .gsub(' ', '_')
      .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
      .gsub(/([a-z\d])([A-Z])/, '\1_\2')
      .downcase
    new_name = result + ext.downcase
  end

  File.join(File.dirname(name), new_name)
end

def rename_recursive(path)
  path = File.expand_path(path)
  Dir[File.join(path, "*")].each do |file|
    is_dir = File.directory?(file)
    new_name = to_snake_case(file, is_dir: is_dir)

    File.rename(file, new_name)
    rename_recursive(new_name) if is_dir
  end
end

if ARGV.empty?
  warn "Usage: ruby snake_rename.rb <path>"
  exit 1
end

rename_recursive(ARGV[0])
