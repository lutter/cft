# Add ../../lib to the search path
$:.unshift(File::join(File::dirname(__FILE__), "..", "..", "lib"))

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
                if s.active?
                    ret = s.stop
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
            File::join(File::dirname(__FILE__), "..", "data", path)
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
            result.delete
            FileUtils::cp_r(datafile(File::join("sessions", name)),
                            Cft::OUTPUT_DIR, :preserve => true)
            result
        end

    end

end
