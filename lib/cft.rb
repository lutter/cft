require 'fam'
require 'fileutils'
require 'find'

module Cft

    # All sessions are stored here
    OUTPUT_DIR = "/tmp/cft"

    # The directories we watch during a session
    WATCH_DIRS = ['/var/run', '/var/lock/subsys', '/etc']

    # Globs that we can definitely ignore
    FILTERS = [ 
               '*.swp', '*.swpx', '*.swx',    # vi leaves these behind
               '*~',                 # emacs backup files
               '/etc/httpd/run/**',  # symlink to /var/run
               '/etc/printcap'       # cups keeps rewriting this
              ]

    # Markers for the changes applied to files
    CHANGED = "="
    CREATED = "+"
    DELETED = "-"

    class Session
        attr_reader :name

        def initialize(name)
            @name = name
        end

        def path(sub = nil)
            path = File::join(OUTPUT_DIR, name)
            unless File::directory?(path)
                FileUtils::mkdir_p(path)
            end
            path = File::join(path, sub) unless sub.nil?
            return path
        end

        def pid
            path("pid")
        end

        def active?
            File::exists?(pid)
        end

        def start(roots = WATCH_DIRS)
            if active?
                puts "Session #{name} already running"
                return 1
            end
            Cft::Puppet::genstate(path("before.yaml"))
            monitor = false
            oldusr1 = trap("SIGUSR1") do
                monitor = true
            end
            fork do 
                $stdout = File::open(path("stdout"), "w")
                $stderr = File::open(path("stderr"), "w")
                $stdin = File::open("/dev/null", "r")
                m = Monitor.new(self, roots)
                m.monitor()
                # The process stopping us by removing the pid file
                # leaves its pid in ppid. Tell it that we are done
                ppid = path("ppid")
                if File::exist?(ppid)
                    File::open(ppid, "r") do |f|
                        id = f.read.chomp.to_i
                        Process::kill("SIGUSR1", id)
                    end
                end
                exit(0)
            end
            slept = 0
            while not monitor and slept < 10
                slept += 0.5
                sleep 0.5
            end
            trap("SIGUSR1", oldusr1)
            if slept >= 10
                puts "Timed out waiting for daemon to start"
                return 1
            end
            return 0
        end

        def stop
            if active?
                ppid = path("ppid")
                File::open(ppid, "w") { |f| f.puts "#{Process::pid}"}
                monitor = false
                oldusr1 = trap("SIGUSR1") do
                    monitor = true
                end
                Cft::Puppet::genstate(path("after.yaml"))
                File::delete(pid)
                slept = 0
                while not monitor and slept < 10
                    slept += 0.5
                    sleep 0.5
                end
                if slept >= 10
                    puts "Timed out waiting for daemon to shut down"
                    return 1
                end
                File::delete(ppid)
                puts "Stopped session #{name}"
                return 0
            else
                puts "Session #{name} not running"
                return 1
            end
        end

        def orig(files)
            unless active?
                puts "Session #{name} is not active"
                return 1
            end
            orig = path("orig")
            unless File::directory?(orig)
                FileUtils::mkdir_p(orig)
            end
            files.each do |f|
                FileUtils::cp_r(f, orig, :preserve => true)
            end
            return 0
        end
        
        def delete
            if active?
                puts "Can't delete active session #{name}"
                return 1
            else
                system("rm -rf #{path}")
                return 0
            end
        end

        def transportable
            Cft::Puppet::transportable(self)
        end

        def change_file
            path("changes")
        end

        def changes
            Changes.new(change_file)
        end

        def source(p = nil)
            if p.nil?
                path("after")
            else
                File::join(path("after"), p)
            end
        end
    end

    class Monitor
        attr_reader :session, :filters

        def initialize(session, roots)
            @session = session
            @lock = session.path("pid")
            @roots = roots
            # All the directories we are watching, includes the trees rooted
            # at all the ROOTS
            @directories = {}
            @bases = {}
            # Store changes to files
            @changes = {}
            @filters = FILTERS
        end
        
        def monitor()
            @fam = Fam::Connection.new(@session.name)
            @fam.no_exists()
            @log = File::open(session.change_file, "w")
        
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
                    raise "No basedir for request #{ev.req} and file #{ev.file}"
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
                    FileUtils::cp_r(c, d, :preserve => true)
                end
            end
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
            Find::find(dir) do |f|
                if File::directory?(f)
                    req = @fam.dir(f)
                    @directories[f] = req
                    @bases[req.num] = f
                end
            end
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
            if ! File::directory?(tgt)
                FileUtils::mkpath(tgt)
            end
            # FIXME: We should try to preserve owenrship/perms/mtime for the
            # directories
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

require 'cft/puppet'
