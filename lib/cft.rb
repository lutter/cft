require 'fam'
require 'fileutils'
require 'yaml'

module Cft

    # All sessions are stored here
    SESSION_DIR = "/tmp/cft"

    # The directories we watch during a session
    WATCH_DIRS = [ 
                  '/etc',
                  '/var/run', '/var/lock/subsys',  # For tracking services
                  '/var/spool/cron'                # vixie-cron crontabs
                 ]

    # Globs that we can definitely ignore
    FILTERS = [ 
               '*.swp', '*.swpx', '*.swx',    # vi leaves these behind
               '*~',                 # emacs backup files
               '/etc/httpd/run/**',  # symlink to /var/run
               '/etc/httpd/logs/**', # symlink to /var/log/httpd
               '/etc/printcap',      # cups keeps rewriting this
               '/etc/ld.so.cache',   # gets recreated a lot
               '/etc/shadow*'        # don't store passwords
              ]

    # Markers for the changes applied to files
    CHANGED = "="
    CREATED = "+"
    DELETED = "-"

    class Error < RuntimeError
    end

    class InternalError < Error
    end

    class Session
        attr_reader :name

        # Map symbolic names for various files/dirs in a sesion
        # to paths/filenames relative to the sessions top dir
        PATHS = { 
            :pid => "pid",               # The lockfile for the session
            :ppid => "ppid",
            :pp_before => "before.yaml", # List of puppet types
            :pp_after => "after.yaml",   # as transportables in yaml
            :rpm_before => "rpm_before.txt", # Dump of installed rpm's
            :rpm_after => "rpm_after.txt",   # before and after
            :rpm_files => "rpm_files.yaml",  # RPM's info on changed files
            :rpm_shadow => "rpm_shadow.yaml",# Dependency info for 
                                             # changed packages
            :stdout => "stdout",         # I/O for the daemon
            :stderr => "stderr",
            :orig => "orig",             # Dir where to store original files
            :changes => "changes",       # File with change listing
            :after => "after",           # Dir with changed files
            :bundle => "bundle"          # Dir for bundle creation
        }

        def initialize(name, session_dir=SESSION_DIR)
            @name = name
            @session_dir = session_dir
        end

        def path(entry = nil)
            path = File::join(@session_dir, name)
            unless File::directory?(path)
                FileUtils::mkdir_p(path)
            end
            unless entry.nil? || entry == :top
                sub = PATHS[entry]
                if sub.nil?
                    raise InternalError, "Invalid session path #{entry}"
                end
                path = File::join(path, sub)
            end
            return path
        end

        def pid
            path(:pid)
        end

        def active?
            File::exists?(pid)
        end

        def exist?
            File::exists?(path(:changes))
        end

        def changes
            unless @changes
                @changes = Changes.new(path(:changes))
            end
            @changes
        end

        def trans(boa = :before)
            fname = path(boa == :before ? :pp_before : :pp_after)
            if File::exist?(fname)
                File::open(fname, "r") { |f|  return YAML::load(f) }
            else
                return TransBucket.new
            end
        end

        def source(p = nil)
            if p.nil?
                path(:after)
            else
                File::join(path(:after), p)
            end
        end
    end

    class Monitor
        attr_reader :session, :filters

        def initialize(session, roots, resume=false)
            @session = session
            @lock = session.path(:pid)
            @roots = roots
            # All the directories we are watching, includes the trees rooted
            # at all the ROOTS
            @directories = {}
            @bases = {}
            @filters = FILTERS
            if resume
                @changes = Changes.new(session.path(:changes)).paths
                @log = File::open(session.path(:changes), "a")
            else
                @changes = {}
                @log = File::open(session.path(:changes), "w")
            end
        end
        
        def monitor()
            @fam = Fam::Connection.new(@session.name)
            @fam.no_exists()

            File::open(@lock, "w") do |f|
                f.puts(Process::pid)
            end
            @fam.file(@lock)
            
            @roots.each { |d| monitor_directory(d) }
                
            Process::kill("SIGUSR1", Process::ppid)
            loop do
                ev = @fam.next_event
                if ev.file == @lock
                    if ev.code == Fam::Event::DELETED
                        break
                    else
                        next
                    end
                end

                dir = @bases[ev.req]
                if dir.nil?
                    $stderr.puts "No basedir for request #{ev.req} and file #{ev.file}"
                    next
                end
                path = File::expand_path(ev.file, dir)

                if ev.code == Fam::Event::CREATED
                    record(path, CREATED)
                    Cft::log("Created %s " % path)
                    monitor_directory(path)
                elsif ev.code == Fam::Event::DELETED
                    Cft::log("Deleted %s" % path)
                    record(path, DELETED)
                    unmonitor_directory(path)
                elsif ev.code == Fam::Event::CHANGED
                    Cft::log("Changed %s" % path)
                    record(path, CHANGED)
                else
                    record(path, ev.code)
                end
            end
            @log.close()
            @fam.close()
            
            preserve_changes
        end
     
        def unmonitor_directory(dir)
            req = @directories.delete(dir)
            unless req.nil?
                @bases.delete(req.num)
                @fam.cancel(req)
            end
        end

        def monitor_directory(dir)
            unless File::directory?(dir) && @directories[dir].nil?
                return
            end
            # FIXME: We should apply filters here already
            req = @fam.dir(dir)
            @directories[dir] = req
            @bases[req.num] = dir
            Dir::entries(dir).reject { |n|
                n == "." || n == ".."
            }.collect { |n|
                File::join(dir, n)
            }.select { |p|
                File::directory?(p)
            }.each { |p|
                monitor_directory(p)
            }
        end

        def record(path, event)
            return if filters.any? { |f| File::fnmatch(f, path) }
            @log.puts "#{path}//#{event}"
            @log.flush()
            @changes[path] ||= []
            @changes[path] << event
        end

        def mkpath(src, dst)
            if File::file?(src)
                src = File::dirname(src)
            end
            tgt = File::join(dst, src)
            unless File::directory?(tgt) || File::symlink?(tgt)
                FileUtils::mkpath(tgt)
            end
            # FIXME: We should try to preserve owenrship/perms/mtime for the
            # directories
        end

        def preserve_changes()
            # Figure out what was changed and squirrel that away
            tgt = session.source
            unless File::directory?(tgt)
                FileUtils::mkdir_p(tgt)
            end
            
            @changes.keys.each do |c|
                Cft::log("#{c} :: #{@changes[c].join(' ')}")
                if File::exist?(c)
                    mkpath(c, tgt)
                    d = File::join(tgt, c)
                    Cft::log("cp -pr #{c} #{d}")
                    # FileUtils::cp_r barfs when you try to copy symlinks
                    # which might become dangling and you use :preserve
                    system("cp -prT #{c} #{d}")
                end
            end
            Cft::RPM::PackageFile::genlist(session.path(:rpm_files), 
                                           @changes.keys)
        end
    end

    class Changes
        attr_reader :paths

        def initialize(filename)
            @paths = {}
            File::open(filename, "r") do |f|
                f.each_line do |l|
                    p, c = l.chomp.split("//")
                    @paths[p] ||= []
                    @paths[p] << c
                end
            end
        end

        def exist?(p)
            c = paths[p]
            if c.nil?
                return nil
            elsif c.size == 0
                return nil
            else
                return c[-1] == CHANGED || c[-1] == CREATED
            end
        end
    end

    def self.log(msg)
        $stdout.puts(msg)
    end
end

require 'cft/commands'
require 'cft/rpm'
# Puppet _must_ be loaded last ... otherwise there's weird interactions
# with the rubygems loading code
require 'cft/puppet'
