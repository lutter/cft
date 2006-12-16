require File::join(File::dirname(__FILE__), "util/harness")

require 'cft'
require 'yaml'

class TestMonitor < Test::Unit::TestCase

    include Cft::Harness

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
        trans = s.transportable
        assert_equal(5, trans.flatten.size)
        assert_not_nil(find_trans(trans, :service, "postfix"))
        [ "/var/lock/subsys/postfix", "/etc/aliases.db",
          "/etc/aliases", "/etc/postfix/main.cf" ].each do |name|
            assert_not_nil(find_trans(trans, :file, name))
        end
    end

    def test_genstate
        Cft::Puppet::genstate("/tmp/state.yaml")
    end

    def test_bluetooth
        Cft::Puppet::Digest::digesters.each do |d|
            puts d.typnam
        end
        s = use_session("bluetooth")
        trans = s.transportable
        # FIXME: Not quite yet
        #assert_equal(1, trans.flatten.size)
        bluetooth = find_trans(trans, :service, "bluetooth")
        assert_not_nil(bluetooth)
        p bluetooth
        assert_equal("stopped", bluetooth[:ensure])
        puts trans.to_manifest
    end

    def find_trans(t, type, name)
        t.find do |to|
            to.type.to_s == type.to_s && to.name == name
        end
    end
end
