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
end
