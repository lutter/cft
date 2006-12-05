require File::join(File::dirname(__FILE__), "util/harness")

require 'cft'

class TestMonitor < Test::Unit::TestCase

    include Cft::Harness

    def test_basic
        s = create_session
        populate({"/etc/nsswitch.conf" => "nsswitch.conf.0",
                  "/etc/mailcap" => "mailcap.0"})
        ret = s.start([ File::join(topdir, "etc") ])
        assert_equal(0, ret)
        populate({"/etc/nsswitch.conf" => "nsswitch.conf.1"})
        ret = s.stop
        assert_equal(0, ret)
        p = s.changes.paths
        assert_equal(1, p.size)
        assert_equal(File::join(topdir, "/etc/nsswitch.conf"), 
                     p.keys[0])
        assert_equal([Cft::CHANGED], p.values[0])
        assert(s.changes.exist?(p.keys[0]))
    end

    def test_basic_manifest
        s = use_session('basic_manifest')
        trans = s.transportable
        list = trans.flatten
        assert_equal(1, list.size)
        file = list[0]
        assert_equal(:file, file.type)
        assert_equal("/etc/nsswitch.conf", file.name)
        assert_equal("0644", file[:mode])
        assert_equal("/tmp/cft/basic_manifest/after/etc/nsswitch.conf", 
                     file[:source])
    end

    def test_postfix
        s = use_session('postfix')
        s.changes.paths.each do |k,v|
            puts "#{k} #{s.changes.paths[k].join("")}"
        end
        trans = s.transportable
        puts trans.to_manifest
    end
end
