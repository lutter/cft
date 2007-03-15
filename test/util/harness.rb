# Add ../../lib and ../ to the search path
$:.unshift(File::join(File::dirname(__FILE__), "..", "..", "lib"))
$:.unshift(File::join(File::dirname(__FILE__), ".."))

# Do whacky stuff to the PATH, so that we can run as a normal user
ENV['PATH'] = "#{ENV['PATH']}:/sbin:/usr/sbin"

# Use the svn version of puppet
begin
    pdir = File::expand_path("~/code/puppet/lib")
    if File::directory? pdir
        $:.unshift(pdir)
    end
end

require 'test/unit'

require 'tmpdir'
require 'fileutils'
require 'cft'

module Cft

    module Harness


        def setup
            @sessions = []
        end

        def teardown
            @sessions.each do |s|
                fin = find_cmd(:finish)
                if s.active?
                    ret = fin.execute(s, [])
                    if ret != 0
                        $stderr.puts "Warning: stopping #{s.name} returned #{ret}"
                    end
                end
                #ret = s.delete
                #if ret != 0
                #    $stderr.puts "Warning: deleting #{s.name} returned #{ret}"
                #end
            end

            if defined? @tmpdir && @tmpdir && File::exists?(@tmpdir)
                system("rm -rf #{@tmpdir}")
            end
            ::Puppet::Type.allclear
            # ::Puppet::Storage.clear
            ::Puppet.clear
        end

        def tmpdir
            unless defined? @tmpdir and @tmpdir
                @tmpdir = File::join(Dir::tmpdir, "cfttest.#{$$}")
            end
            unless File::exists?(@tmpdir)
                FileUtils.mkdir_p(@tmpdir)
                File.chmod(01777, @tmpdir)
            end
            return @tmpdir
        end

        def topdir
            File::join(tmpdir, "root")
        end

        def mktmpdir(path)
            dir = File::join(tmpdir, path)
            FileUtils::mkdir_p(dir)
            return dir
        end

        def populate(map)
            map.each do |dst, src|
                src = datafile(src)
                dst = File::join(topdir, dst)
                dpath = File::dirname(dst)
                unless File::exist?(src)
                    raise "Datafile #{src} not found"
                end
                unless File::exist?(dpath)
                    FileUtils::mkdir_p(dpath)
                end
                FileUtils::cp_r(src, dst, :preserve => true)
            end
        end

        def datafile(path)
            p = File::join(File::dirname(__FILE__), "..", "data", path)
            return File::expand_path(p)
        end

        # Create an fresh session
        def create_session
            result = Cft::Session.new("test")
            @sessions << result
            return result
        end

        # Use a prepared session from test/data/sessions
        def use_session(name)
            result = Cft::Session.new(name)
            cmd = find_cmd(:erase)
            cmd.execute(result, [])
            src = datafile(File::join("sessions", name))
            dst = Cft::OUTPUT_DIR
            if File::exist?("#{src}.tgz")
                system("tar xzf #{src}.tgz -C #{dst}")
            elsif File::directory?(src)
                system("cp -pr #{src} #{dst}")
            else
                raise "Could not find session #{name}"
            end
            result
        end

        # Find the command with the given name
        def find_cmd(name)
            l = Cft::Commands::Base::find(name)
            assert_equal(1, l.size)
            l[0]
        end

        # Assert that the resource _type_[_name_] in _trans_
        # exists and has the attributes listed in _hash_ with
        # the values from _hash_
        def assert_resource(trans, type, name, hash = {})
            res = trans.find_obj(type, name)
            assert_not_nil(res, "Could not find #{type}[#{name}]")
            hash.each do |k, v|
                assert_equal(v, res[k], "Property #{k} for #{type}[#{name}]")
            end
        end

    end

end
