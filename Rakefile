# Rakefile for cft -*- ruby -*-
require 'rake/clean'
require 'rake/testtask'
require 'rake/packagetask'

PKG_NAME='cft'
PKG_VERSION='0.0.1'

PKG_FILES = FileList[
  "Rakefile", "AUTHORS", "COPYING", "INSTALL", "README", "TODO",
  "bin/cft",
  "lib/**/*.rb",
  "test/**/*"
]

Rake::PackageTask.new("package") do |p|
  p.name = PKG_NAME
  p.version = PKG_VERSION
  p.need_tar = true
  p.need_zip = true
  p.package_files = PKG_FILES
end

Rake::TestTask.new(:test) do |t|
  t.test_files = FileList['test/tc_*.rb']
end
