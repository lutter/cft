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

    def test_transdiff
        before = Cft::RPM::readstate(datafile("rpm/pkgs.txt"))
        after = Cft::RPM::readstate(datafile("rpm/pkgs-after.txt"))
        tb_bef, tb_aft = Cft::RPM::transdiff(before, after)
        exp_bef = { 
            'dhcpv6_client.i386' => '0:0.10-32.fc6',
            'mkinitrd.i386' => '0:5.1.19-1',
            'nash.i386' => '0:5.1.19-1'
        }
        exp_aft = {
            'mkinitrd.i386' => '0:5.1.19.0.2-1',
            'nash.i386' => '0:5.1.19.0.2-1',
            'gamin.i386' => '0:0.1.7-8.fc6'
        }
        assert_package_bucket(exp_bef, tb_bef)
        assert_package_bucket(exp_aft, tb_aft)
    end

    def test_byfile
        Cft::RPM::withdb do |db|
            pkgs = Cft::RPM::byfile(db, "/bin/sh")
            assert_equal(1, pkgs.size)
            assert_equal('bash', pkgs[0].name)
            assert_equal("/bin/sh", pkgs[0].file.path)
            
            pkgs = Cft::RPM::byfile(db, "/etc/sysconfig/")
            assert_equal(1, pkgs.size)
            assert_equal('filesystem', pkgs[0].name)
            assert_equal("/etc/sysconfig", pkgs[0].file.path)
            
            pkgs = Cft::RPM::byfile(db, " /not /a /file")
            assert_equal(0, pkgs.size)
        end
    end

    def test_filelist
        fname = File::join(tmpdir, "files.txt")
        files = [ "/bin/sh", "/bin/bash", "/etc/sysconfig/",
                  " /not /a /file" ]
        pkgs = nil
        assert_nothing_raised {
            Cft::RPM::PackageFile::genlist(fname, files)
            pkgs = Cft::RPM::PackageFile::readlist(fname)
        }
        assert_equal(3, pkgs.size)
        assert_equal('bash', pkgs[0].name)
        assert_equal("/bin/sh", pkgs[0].file.path)

        assert_equal('bash', pkgs[1].name)
        assert_equal("/bin/bash", pkgs[1].file.path)

        assert_equal('filesystem', pkgs[2].name)
        assert_equal("/etc/sysconfig", pkgs[2].file.path)
    end

    def test_filelist_load
        pkgs = nil
        assert_nothing_raised {
            fname = datafile("rpm/filelist.txt")
            pkgs = Cft::RPM::PackageFile::readlist(fname)
        }
        assert_equal(3, pkgs.size)
        pkgs.each do |p|
            assert_equal('i386', p.arch)
            assert_equal('root', p.file.owner)
            assert_equal('root', p.file.group)
        end
        assert_equal('bash', pkgs[0].name)
        assert_equal("/bin/sh", pkgs[0].file.path)
        assert_equal('0:3.1-16.1', pkgs[0].version.to_vre)
        assert_equal('bash', pkgs[0].file.link_to)
        assert_equal(0777, pkgs[0].file.mode)

        assert_equal('bash', pkgs[1].name)
        assert_equal("/bin/bash", pkgs[1].file.path)
        assert_equal('0:3.1-16.1', pkgs[1].version.to_vre)
        assert_nil(pkgs[1].file.link_to)
        assert_equal(0755, pkgs[1].file.mode)

        assert_equal('filesystem', pkgs[2].name)
        assert_equal("/etc/sysconfig", pkgs[2].file.path)
        assert_equal('0:2.4.0-1', pkgs[2].version.to_vre)
        assert_nil(pkgs[2].file.link_to)
        assert_equal(0755, pkgs[2].file.mode)
    end

    private
    def assert_pkg_evr(vre, pkg)
        assert_not_nil(pkg)
        assert_equal(1, pkg.size)
        assert_equal(vre, pkg[0].to_vre)
    end
    
    def assert_package_bucket(exp, bucket)
        assert_equal(exp.size, bucket.flatten.size)
        exp.each do |na, v|
            assert_resource(bucket, :package, na,
                            :ensure => v)
        end
    end
end
