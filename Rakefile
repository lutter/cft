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
  "cft.spec",
  "bin/cft",
  "lib/**/*.rb",
  "test/**/*"
]

DIST_FILES = FileList[
  "pkg/*.rpm",  "pkg/*.gem",  "pkg/*.zip", "pkg/*.tgz"
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

desc "Build (S)RPM for #{PKG_NAME}"
task :rpm => [ :package ] do |t|
    Dir::chdir("pkg")
    dir = Dir::getwd()
    puts "Building RPM"
    system("rpmbuild --define '_topdir #{dir}' --define '_sourcedir #{dir}' --define '_srcrpmdir #{dir}' --define '_rpmdir #{dir}' -ba ../#{PKG_NAME}.spec > rpmbuild.log 2>&1")
end

desc "Release a version to the site"
task :dist => [ ] do |t|
    puts "Copying files"
    system "scp -p #{DIST_FILES.to_s} lutter@et.redhat.com:/var/www/sites/cft.et.redhat.com/download"
    puts "Making release links"
    system "ssh lutter@et.redhat.com /home/lutter/bin/cft-release #{PKG_VERSION}"
end
