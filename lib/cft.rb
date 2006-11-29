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
               '*.swp', '*.swpx',    # vi leaves these behind
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
            File::exist?(pid)
        end

        def start
            if active?
                puts "Session #{name} already running"
                return 1
            end
            fork do 
                File::open(pid, "w") do |f|
                    f.puts(Process::pid)
                end
                $stdout = File::open(path("stdout"), "w")
                $stderr = File::open(path("stderr"), "w")
                $stdin = File::open("/dev/null", "r")
                m = Monitor.new(self, WATCH_DIRS)
                m.monitor()
            end
        end

        def stop
            if active?
                File::delete(pid)
                puts "Stopped session #{name}"
                return 0
            else
                puts "Session #{name} not running"
                return 1
            end
        end

        def orig(files)
            orig = path("orig")
            unless File::directory?(orig)
                FileUtils::mkdir_p(orig)
            end
            files.each do |f|
                FileUtils::cp_r(f, orig, :preserve => true)
            end
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
            @log = File::open(session.path("changes"), "w")
        
            @roots.each { |d| monitor_directory(d) }
                
            @fam.file(@lock)
        
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
            tgt = session.path("after")
            unless File::directory?(tgt)
                FileUtils::mkdir_p(tgt)
            end
            
            @changes.keys.each do |c|
                Cft::log("#{c} :: #{@changes[c].join(' ')}")
                if File::file?(c)
                    Cft::log("cp -pr #{c} #{tgt}")
                    FileUtils::cp_r(c, tgt, :preserve => true)
                end
            end
        end
     
        def unmonitor_directory(dir)
            req = @directories.delete(dir)
            unless req.nil?
                @bases.del(req.num)
                @fam.cancel(req)
            end
        end

        def monitor_directory(dir)
            unless File::directory?(dir) && @directories[dir].nil?
                return
            end
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
    end

    def self.log(msg)
        $stdout.puts(msg)
    end
end
