require File::join(File::dirname(__FILE__), "util/harness")

require 'cft'
require 'yaml'

class TestMonitor < Test::Unit::TestCase

    include Cft::Harness

    # Create a tricky symlink situation that httpd actually has
    # and that caused failures in preserve_changes
    def test_nested_bad_symlink
        s = create_session
        watched = mktmpdir("watched")
        unwatched = mktmpdir("unwatched")

        mon = Cft::Monitor.new(s, watched)
        def Cft::log(msg) ; end # Dodgy way to turn off log output

        src = File::join(unwatched, "src")
        Dir::mkdir(src)
                
        dir = File::join(watched, "dir")
        lnk = File::join(dir, "link")
        Dir::mkdir(dir)
        File::symlink("../../unwatched/src", lnk)
        assert(File::exist?(lnk))

        mon.record(dir, Cft::CREATED)
        mon.preserve_changes
        mon.record(lnk, Cft::CREATED)
        mon.record(lnk, Cft::CHANGED)
        assert_nothing_raised { mon.preserve_changes }
    end
end
