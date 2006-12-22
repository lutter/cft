# Rakefile for cft -*- ruby -*-
require 'rake/clean'
require 'rake/testtask'
require 'rake/packagetask'
require 'rake/gempackagetask'

begin
    require 'rubygems'
rescue LoadError
end

PKG_NAME='cft'
PKG_VERSION='0.0.1'

PKG_FILES = FileList[
  "Rakefile", "AUTHORS", "COPYING", "INSTALL", "README", "TODO",
  "bin/cft",
  "lib/**/*.rb",
  "test/**/*"
]

Rake::TestTask.new(:test) do |t|
  t.test_files = FileList['test/tc_*.rb']
end

if defined?(Gem)
    spec = Gem::Specification.new do |s|
        s.platform = Gem::Platform::RUBY
        s.summary = "Config file tracker"
        s.name = 'cft'
        s.homepage = 'http://cft.et.redhat.com/'
        s.version = PKG_VERSION
        s.add_dependency('puppet')
        s.add_dependency('ruby-fam')
        s.require_path = 'lib'
        s.autorequire = 'puppet'
        s.files = PKG_FILES
        s.description = <<EOF
Cft (pronounced 'sift') follows a sysadmin as she makes changes to the
system, records the changes and produces a puppet manifest from them.  Its
basic workings are inspired by Gnome's Sabayon, a tool that watches a user
make configuration changes to their desktop and collects them into a
reusable bundle. Instead of the desktop though, cft is focused on
traditional system admins and how they maintain machines, mostly with
command line tools. Cft uses puppet as its backbone for expressing the
configuration of a system, and for understanding in greater detail what
changes the admin has made to the system.
EOF
    end # ' Make emacs happy

    Rake::GemPackageTask.new(spec) do |pkg|
        pkg.need_zip = true
        pkg.need_tar = true
    end
else
    Rake::PackageTask.new("package") do |p|
        p.name = PKG_NAME
        p.version = PKG_VERSION
        p.need_tar = true
        p.need_zip = true
        p.package_files = PKG_FILES
    end
end
