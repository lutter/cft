require File::join(File::dirname(__FILE__), "util/harness")

require 'cft'
require 'yaml'

class TestMonitor < Test::Unit::TestCase

    include Cft::Harness

    def test_genstate
        gs_fname = File::join(tmpdir, "rpm_gs.txt")
        Cft::RPM::genstate(gs_fname, datafile("rpm"))
        gs = Cft::RPM::readstate(gs_fname)
        gs.each { |k, v| v.sort! }
        ps = Cft::RPM::readstate(datafile("rpm/pkgs.txt"))
        ps.each { |k, v| v.sort! }
        (gs.keys + ps.keys).uniq.each do |na|
            assert_equal(ps[na], gs[na], "package #{na}")
        end
    end

    def test_diff
        before = Cft::RPM::readstate(datafile("rpm/pkgs.txt"))
        after = Cft::RPM::readstate(datafile("rpm/pkgs-after.txt"))
        diff = Cft::RPM::diff(before, after)
        e, i, u = diff[:erased], diff[:installed], diff[:updated]
        # erased: dhcpv6_client.i386 0 0.10 32.fc6
        # installed: gamin.i386 0 0.1.7 8.fc6
        # updated: mkinitrd.i386 0 5.1.19.0.2 1
        #          nash.i386 0 5.1.19.0.2 1
        assert_equal(1, e.size)
        assert_pkg_evr("0:0.10-32.fc6", e["dhcpv6_client.i386"])
        
        assert_equal(1, i.size)
        assert_pkg_evr("0:0.1.7-8.fc6", i["gamin.i386"])

        assert_equal(2, u.size)
        assert_pkg_evr("0:5.1.19.0.2-1", u["mkinitrd.i386"])
        assert_pkg_evr("0:5.1.19.0.2-1", u["nash.i386"])
    end

    private
    def assert_pkg_evr(vre, pkg)
        assert_not_nil(pkg)
        assert_equal(1, pkg.size)
        assert_equal(vre, pkg[0].to_vre)
    end
end
