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
        ps = Cft::RPM::readstate(datafile("rpm/pkgs-after.txt"))
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
        # erased: gamin.i386 0:0.1.7-8.fc6
        # installed: yum.noarch 0:3.0-6
        # updated: python-sqlite.i386 0:1.1.7-1.2.1
        #          procps.i386 0:3.2.7-8
        #          sqlite.i386 0:3.3.6-2
        assert_equal(1, e.size)
        assert_pkg_evr("0:0.1.7-8.fc6", e["gamin.i386"])
        
        assert_equal(1, i.size)
        assert_pkg_evr("0:3.0-6", i["yum.noarch"])

        assert_equal(3, u.size)
        assert_pkg_evr("0:1.1.7-1.2.1", u["python-sqlite.i386"])
        assert_pkg_evr("0:3.2.7-8", u["procps.i386"])
        assert_pkg_evr("0:3.3.6-2", u["sqlite.i386"])
    end

    def test_transdiff
        before = Cft::RPM::readstate(datafile("rpm/pkgs.txt"))
        after = Cft::RPM::readstate(datafile("rpm/pkgs-after.txt"))
        tb_bef, tb_aft = Cft::RPM::transdiff(before, after)
        exp_bef = {
            'gamin.i386' => '0:0.1.7-8.fc6',
            'python-sqlite.i386' => '0:1.1.7-1.2.0',
            'procps.i386' => '0:3.2.7-7',
            'sqlite.i386' => '0:3.3.6-1'
        }
        exp_aft = {
            'yum.noarch' => '0:3.0-6',
            'python-sqlite.i386' => '0:1.1.7-1.2.1',
            'procps.i386' => '0:3.2.7-8',
            'sqlite.i386' => '0:3.3.6-2'
        }
        assert_package_bucket(exp_bef, tb_bef)
        assert_package_bucket(exp_aft, tb_aft)
    end

    def test_byfile
        Cft::RPM::withdb do |db|
            pkgs = Cft::RPM::byfile(db, "/bin/sh")
            assert_equal(1, pkgs.size)
            assert_equal('bash', pkgs[0].package.name)
            assert_equal("/bin/sh", pkgs[0].path)
            assert_equal("/bin/bash", pkgs[0].file.path)
            
            pkgs = Cft::RPM::byfile(db, "/etc/sysconfig/")
            assert_equal(1, pkgs.size)
            assert_equal('filesystem', pkgs[0].package.name)
            assert_equal("/etc/sysconfig", pkgs[0].path)
            assert_equal("/etc/sysconfig", pkgs[0].file.path)

            pkgs = Cft::RPM::byfile(db, "/etc/init.d/killall")
            assert_equal(1, pkgs.size)
            assert_equal('initscripts', pkgs[0].package.name)
            assert_equal("/etc/init.d/killall", pkgs[0].path)
            assert_equal("/etc/rc.d/init.d/killall", pkgs[0].file.path)
            
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
        assert_equal("/bin/sh", pkgs[0].path)
        assert_equal("/bin/bash", pkgs[0].file.path)

        assert_equal('bash', pkgs[1].name)
        assert_equal("/bin/bash", pkgs[1].path)
        assert_equal("/bin/bash", pkgs[1].file.path)

        assert_equal('filesystem', pkgs[2].name)
        assert_equal("/etc/sysconfig", pkgs[2].path)
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
            assert_nil(p.file.link_to)
            assert_equal(0755, p.file.mode)
        end
        assert_equal('bash', pkgs[0].name)
        assert_equal("/bin/sh", pkgs[0].path)
        assert_equal("/bin/bash", pkgs[0].file.path)
        assert_equal('0:3.1-16.1', pkgs[0].version.to_vre)

        assert_equal('bash', pkgs[1].name)
        assert_equal("/bin/bash", pkgs[1].path)
        assert_equal("/bin/bash", pkgs[1].file.path)
        assert_equal('0:3.1-16.1', pkgs[1].version.to_vre)

        assert_equal('filesystem', pkgs[2].name)
        assert_equal("/etc/sysconfig", pkgs[2].path)
        assert_equal("/etc/sysconfig", pkgs[2].file.path)
        assert_equal('0:2.4.0-1', pkgs[2].version.to_vre)
    end

    def test_filelist_not_there
        fname = File::join(tmpdir, "no such file")
        pkgs = nil
        assert_nothing_raised {
            pkgs = Cft::RPM::PackageFile::readlist(fname)
        }
        assert_equal([], pkgs)
    end

    def test_shadow
        Cft::RPM::withdb(datafile("rpm")) do |db|
            i = package(db, 'initscripts')
            c = package(db, 'chkconfig')
            g = package(db, 'glibc')
            b = package(db, 'basesystem')
            shadow = Cft::RPM::shadow([i, c, g, b])
            exp = {
                i => [ c, g ],
                c => [ g ],
                g => [ b ],
                b => []
            }
            assert_equal(exp, shadow)
        end
    end

    def test_genshadow
        before_file = datafile("rpm/pkgs.txt")
        after_file = datafile("rpm/pkgs-after.txt")
        root = datafile("rpm")
        shadow_file = File::join(tmpdir, "shadow.yaml")
        sh = Cft::RPM::genshadow(shadow_file, before_file, after_file, root)
        # Convert all those PackageHandles into strings
        shs = {}
        sh.each { |k,v| shs[k.to_s] = v.collect { |x| x.to_s } }
        exp = { 
            "procps-3.2.7-8.i386" => [],
            "sqlite-3.3.6-2.i386" => [],
            "yum-3.0-6.noarch" => ["python-sqlite-1.1.7-1.2.1.i386"],
            "python-sqlite-1.1.7-1.2.1.i386" => ["sqlite-3.3.6-2.i386"]
        }
        assert_equal(exp, shs)
        # Check we can read it back, too
        shr = Cft::RPM::readshadow(shadow_file)
        assert_equal(4, sh.size)
        assert_equal(sh.keys.sort, shr.keys.sort)
        sh.keys.each { |k| assert_equal(sh[k].sort, shr[k].sort) }
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

    def package(db, name)
        db.each_match(RPM::TAG_NAME, name) { |k| return k }
    end
end
