require File::join(File::dirname(__FILE__), "util/harness")

require 'cft'

class TestSession < Test::Unit::TestCase

    include Cft::Harness

    def test_basic
        s = create_session
        populate({"/etc/nsswitch.conf" => "nsswitch.conf.0",
                  "/etc/mailcap" => "mailcap.0"})

        cmd = find_cmd(:begin)
        class << cmd ; attr_writer :roots ; end
        cmd.roots = File::join(topdir, "etc")
        ret = cmd.execute(s, [])
        assert_equal(0, ret)

        populate({"/etc/nsswitch.conf" => "nsswitch.conf.1"})
        ret = find_cmd(:finish).execute(s, [])
        assert_equal(0, ret)

        p = s.changes.paths
        assert_equal(1, p.size)
        assert_equal(File::join(topdir, "/etc/nsswitch.conf"), 
                     p.keys[0])
        assert_equal([Cft::CHANGED], p.values[0])
        assert(s.changes.exist?(p.keys[0]))
    end

    def test_path
        s = create_session
        assert_equal(File::join(Cft::OUTPUT_DIR, s.name, "pid"), s.pid)
        assert_raise(Cft::InternalError) {
            s.path(:xyzzy)
        }
    end

end
