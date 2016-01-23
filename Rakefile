# -*- ruby -*-

require "rdoc/task"
require 'rake/testtask'

task :default => :test

Rake::TestTask.new do |t|
  t.pattern = "features/test*.rb"
end

task :env do
  $:.unshift '.'
end

task :irb => :env do
  ARGV.clear
  ENV['IRB'] = 'true'
  require 'irb'
  require 'init'

  IRB.start
end

RDoc::Task.new do |rdoc|
  rdoc.main = "README.rdoc"
  rdoc.rdoc_files.include("{lib/features}/**/*.rb")
  rdoc.rdoc_dir = "public/rdoc"
end

RDoc::Task.new(:rdoc => "rdoc", :clobber_rdoc => "rdoc:clean",
               :rerdoc => "rdoc:force")

# vim: syntax=ruby
