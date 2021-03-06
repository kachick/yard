# frozen_string_literal: true
require "rubygems"
begin
  require "rspec"
rescue LoadError
  require "spec"
end

begin
  require 'bundler/setup'
rescue LoadError
  nil # noop
end

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib', 'yard'))

unless defined?(HAVE_RIPPER)
  begin require 'ripper'; rescue LoadError; nil end
  HAVE_RIPPER = defined?(::Ripper) && !ENV['LEGACY'] ? true : false
  LEGACY_PARSER = !HAVE_RIPPER

  class YARD::Parser::SourceParser
    def self.parser_type; @parser_type == :ruby ? :ruby18 : @parser_type end
  end if ENV['LEGACY']
end

begin
  require 'coveralls'
  Coveralls.wear!
end if ENV['CI'] && HAVE_RIPPER

NAMED_OPTIONAL_ARGUMENTS = RUBY_VERSION >= '2.1.0'

def parse_file(file, thisfile = __FILE__, log_level = log.level, ext = '.rb.txt')
  Registry.clear
  path = File.join(File.dirname(thisfile), 'examples', file.to_s + ext)
  YARD::Parser::SourceParser.parse(path, [], log_level)
end

def described_in_docs(klass, meth, file = nil)
  YARD::Tags::Library.define_tag "RSpec Specification", :it, :with_raw_title_and_text

  # Parse the file (could be multiple files)
  if file
    filename = File.join(YARD::ROOT, file)
    YARD::Parser::SourceParser.new.parse(filename)
  else
    underscore = klass.class_name.gsub(/([a-z])([A-Z])/, '\1_\2').downcase.gsub('::', '/')
    $LOADED_FEATURES.find_all {|p| p.include? underscore }.each do |found_fname|
      next unless File.exist? found_fname
      YARD::Parser::SourceParser.new.parse(found_fname)
    end
  end

  # Get the object
  objname = klass.name + (meth[0, 1] == '#' ? meth : '::' + meth)
  obj = Registry.at(objname)
  raise "Cannot find object #{objname} described by spec." unless obj
  raise "#{obj.path} has no @it tags to spec." unless obj.has_tag? :it

  # Run examples
  describe(klass, meth) do
    obj.tags(:it).each do |it|
      path = File.relative_path(YARD::ROOT, obj.file)
      it(it.name + " (from #{path}:#{obj.line})") do
        begin
          eval(it.text)
        rescue => e
          e.set_backtrace(["#{path}:#{obj.line}:in @it tag specification"])
          raise e
        end
      end
    end
  end
end

def docspec(objname = self.class.description, klass = self.class.described_type)
  # Parse the file (could be multiple files)
  underscore = klass.class_name.gsub(/([a-z])([A-Z])/, '\1_\2').downcase.gsub('::', '/')
  $LOADED_FEATURES.find_all {|p| p.include? underscore }.each do |filename|
    filename = File.join(YARD::ROOT, filename)
    next unless File.exist? filename
    YARD::Parser::SourceParser.new.parse(filename)
  end

  # Get the object
  objname = klass.name + objname if objname =~ /^[^A-Z]/
  obj = Registry.at(objname)
  raise "Cannot find object #{objname} described by spec." unless obj
  raise "#{obj.path} has no @example tags to spec." unless obj.has_tag? :example

  # Run examples
  obj.tags(:example).each do |exs|
    exs.text.split(/\n/).each do |ex|
      begin
        hash = eval("{ #{ex} }")
        expect(hash.keys.first).to eq hash.values.first
      rescue => e
        raise e, "#{e.message}\nInvalid spec example in #{objname}:\n\n\t#{ex}\n"
      end
    end
  end
end

module Kernel
  require 'cgi'

  def p(*args)
    puts args.map {|arg| CGI.escapeHTML(arg.inspect) }.join("<br/>\n")
    args.first
  end

  def puts(str = '')
    STDOUT.puts str + "<br/>\n"
    str
  end
end if ENV['TM_APP_PATH']

RSpec.configure do |config|
  config.before(:each) { log.io = StringIO.new }

  # isolate environment of each test
  # any other global settings which might be modified by a test should also
  # be saved and restored here
  config.around(:each) do |example|
    saved_level = log.level
    example.run
    log.level = saved_level
  end
end

include YARD
