require File::join(File::dirname(__FILE__), "util/harness")

require 'cft'
require 'yaml'

class TestMonitor < Test::Unit::TestCase

    include Cft::Harness

    def test_basic_manifest
        s = use_session('basic_manifest')
        digest = Cft::Puppet::Digest.new(s)
        trans = digest.transportable
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
        digest = Cft::Puppet::Digest.new(s)
        trans = digest.transportable
        #assert_equal(4, trans.flatten.size)
        assert_not_nil(find_trans(trans, :service, "postfix"))
        [ "/etc/aliases.db", "/etc/aliases", 
          "/etc/postfix/main.cf" ].each do |name|
            assert_not_nil(find_trans(trans, :file, name))
        end
    end

    def test_postfix_bundle
        s = use_session('postfix')
        digest = Cft::Puppet::Digest.new(s)
        bundle = File::join(tmpdir, "bundle.tgz")
        digest.create_bundle(bundle)
        assert(File::exist?(bundle))
        files = %x{tar tzf #{bundle}}.split.sort
        assert_equal(0, $?.exitstatus)
        assert_equal(["bundle/", "bundle/aliases", "bundle/aliases.db", 
                      "bundle/main.cf", "bundle/manifest.pp"],
                     files)
    end

    def test_genstate
        assert_nothing_raised {
            Cft::Puppet::genstate("/tmp/state.yaml")
        }
    end

    def test_bluetooth_transportable
        s = use_session("bluetooth")
        digest = Cft::Puppet::Digest.new(s)
        trans = digest.transportable
        # FIXME: Not quite yet, we have spurious subdaemons in the result
        #assert_equal(1, trans.flatten.size)
        bluetooth = find_trans(trans, :service, "bluetooth")
        assert_not_nil(bluetooth)
        assert_equal("stopped", bluetooth[:ensure])
    end

    def test_bluetooth_diff
        s = use_session("bluetooth")
        digest = Cft::Puppet::Digest.new(s)
        digest.after.delete_obj(:service, "psacct")
        digest.before.delete_obj(:user, "adm")

        diff = digest.diff
        assert_equal(3, diff.length)

        psacct = diff.find_obj(:service, "psacct")
        assert_not_nil(psacct)
        assert_equal(:absent, psacct[:ensure])

        bluetooth = diff.find_obj(:service, "bluetooth")
        assert_not_nil(bluetooth)
        assert_equal(:false, bluetooth[:enable])
        # Should really be 'stopped' but that's a problem
        # with puppet, not cft
        assert_equal(:running, bluetooth[:ensure])

        adm = diff.find_obj(:user, "adm")
        assert_not_nil(adm)
        assert_equal(:present, adm[:ensure])
        assert_equal("/var/adm", adm[:home])
    end

    def find_trans(t, type, name)
        t.find do |to|
            to.type.to_s == type.to_s && to.name == name
        end
    end
end
