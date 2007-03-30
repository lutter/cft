# Support for the cft command line; each subcommand is its own instance
# of (a subclass of) +Cft::Commands::Base+ with its own options etc.
module Cft::Commands

    class Base
        attr_reader :name
        class << self
            attr_reader :cmds, :main

            # Create a new command with name +n+. If +n+ is +:main+, the
            # command is the main entry point for the program, otherwise
            # it's a subcommand
            def newcommand(n, &block)
                cmd = Class.new(Base)
                cmd.class_eval(&block)
                if n == :main
                    @main = cmd.new(n)
                else
                    @cmds ||= {}
                    @cmds[n] = cmd.new(n)
                end
            end

            def doc(txt)
                define_method(:doc) { txt }
            end

            def require_session(errs)
                define_method(:create_session) do |argv, global_opts|
                    if argv.size < 1
                        $stderr.puts "Missing session name"
                        $stderr.puts opts
                        return nil
                    else
                        s = Cft::Session.new(argv.shift, 
                                             global_opts[:session_dir])
                        if errs[:active] && s.active?
                            $stderr.puts "Session #{s.name}: #{errs[:active]}"
                            return nil
                        elsif errs[:inactive] && ! s.active?
                            $stderr.puts "Session #{s.name}: #{errs[:inactive]}"
                            return nil
                        elsif errs[:missing] && ! s.exist?
                            $stderr.puts "Session #{s.name}: #{errs[:missing]}"
                            return nil
                        end
                        return s
                    end
                end
            end

            def find(name)
                name = name.to_s.downcase
                cmds.keys.map { 
                    |k| k.to_s.downcase 
                }.select { 
                    |k| k.index(name) == 0 
                }.collect {
                    |k| cmds[k.to_sym]
                }
            end

            def cmds
                @cmds ||= {}
                @cmds
            end
        end

        def initialize(name)
            @name = name
        end

        def opts(banner = nil)
            OptionParser.new(banner)
        end

        newcommand(:main) do

            def initialize(name)
                super
                @global_opts = {
                    :session_dir => ENV["CFT_SESSION_DIR"] || Cft::SESSION_DIR
                }
            end

            def opts
                name = File::basename $0
                opts = OptionParser.new("#{name} GLOBAL_OPTS MODE OPTS")
                opts.separator("  Follow changes made to the system and extract them into a puppet manifest")
                opts.separator("")
                opts.separator "Modes:"
                Base::cmds.keys.map { 
                    |k| k.to_s 
                }.sort.each do |k|
                    opts.separator "    %s%s%s" % [k, " " * (33-k.size), Base::cmds[k.to_sym].doc]
                end
                opts.separator "Run #{name} MODE --help for help on a mode's options"
                opts.separator ""
                
                opts.separator "Global options:"
                opts.on("-s", "--session-dir DIR", 
                  "Store sessions in DIR instead of #{Cft::SESSION_DIR}") do
                    |val|  @global_opts[:session_dir] = val 
                end
                return opts
            end

            def execute(argv)
                gopts = self.opts
                name = "help"
                rest = []
                begin
                    rest = gopts.order(argv) do |arg|
                        name = arg
                        gopts.terminate
                    end
                rescue OptionParser::InvalidOption => detail
                    $stderr.puts detail
                    $stderr.puts gopts
                    exit(1)
                end
                found_cmds = Base::find(name)
                if found_cmds.empty?
                    $stderr.puts "Unknown mode #{name}" unless name == "help"
                    $stderr.puts gopts
                    exit(1)
                elsif found_cmds.size > 1
                    names = found_cmds.map { |c| c.name }.join(", ")
                    $stderr.puts "Ambiguous mode #{name}: matches #{names}" unless name == "help"
                    $stderr.puts gopts
                    exit(1)
                end
                cmd = found_cmds[0]
                
                opts = cmd.opts
                
                begin
                    rest = opts.order(rest)
                rescue OptionParser::InvalidOption => detail
                    $stderr.puts detail
                    $stderr.puts opts
                    exit(1)
                end
                
                if cmd.respond_to?(:create_session)
                    session = cmd.create_session(rest, @global_opts)
                    return 1 if session.nil?
                    return cmd.execute(session, rest)
                else
                    return cmd.execute(rest)
                end
            end
        end

        newcommand(:begin) do
            doc "Start a new session"
            attr_reader :roots

            def initialize(name)
                super(name)
                @roots = Cft::WATCH_DIRS
                @resume = false
            end

            def opts
                opts = super("cft begin [options] SESSION")
                opts.on("-r", "--resume", 
                        "Bundle manifest and needed files") do |val|
                    @resume = true
                end
                opts
            end

            require_session :active => "already running"

            def execute(session, args)
                unless @resume
                    Cft::Puppet::genstate(session.path(:pp_before))
                    Cft::RPM::genstate(session.path(:rpm_before))
                end
                monitor = false
                oldusr1 = trap("SIGUSR1") do
                    monitor = true
                end
                fork do
                    mode = @resume ? "a" : "w"
                    $stdout = File::open(session.path(:stdout), mode)
                    $stderr = File::open(session.path(:stderr), mode)
                    $stdin = File::open("/dev/null", "r")
                    begin
                        m = Cft::Monitor.new(session, roots, @resume)
                        m.monitor()
                    rescue => detail
                        $stderr.puts "Monitoring failed: #{detail} at"
                        $stderr.puts detail.backtrace
                    end
                    # The process stopping us by removing the pid file
                    # leaves its pid in ppid. Tell it that we are done
                    ppid = session.path(:ppid)
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
        end

        newcommand(:finish) do
            doc "Finish a running session"

            def opts
                opts = super("cft finish [options] SESSION")
                opts
            end

            require_session :inactive => "not running"

            def execute(session, args)
                ppid = session.path(:ppid)
                File::open(ppid, "w") { |f| f.puts "#{Process::pid}"}
                monitor = false
                oldusr1 = trap("SIGUSR1") do
                    monitor = true
                end
                Cft::Puppet::genstate(session.path(:pp_after))
                Cft::RPM::genstate(session.path(:rpm_after))
                File::delete(session.pid)
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
                puts "Stopped session #{session.name}"
                return 0
            end
        end

        newcommand(:orig) do
            doc "Store files as originals"
            
            def opts
                opts = super("cft orig [options] SESSION FILES")
                opts
            end

            require_session :inactive => "is not active"

            def execute(session, args)
                orig = session.path(:orig)
                unless File::directory?(orig)
                    FileUtils::mkdir_p(orig)
                end
                argv.each do |f|
                    FileUtils::cp_r(f, orig, :preserve => true)
                end
                return 0
            end
        end

        newcommand(:erase) do
            doc "Erase a session completely"
            
            def opts
                opts = super("cft erase [options] SESSION")
                opts
            end

            require_session :active => "Can't delete active session"

            def execute(session, args)
                system("rm -rf #{session.path}")
                return 0
            end
        end

        newcommand(:manifest) do
            doc "Generate a puppet manifest"
            
            def opts
                opts = super("cft manifest [options] SESSION")
                opts.separator "Generate a puppet manifest from a finished session"
                opts.on("-b", "--bundle FILE", 
                        "Bundle manifest and needed files") do |val|
                    @bundle = val
                end
                opts
            end

            require_session :active => "Can't generate from an active session",
              :missing => "Could not find session"

            def execute(session, args)
                digest = Cft::Puppet::Digest.new(session)
                if @bundle
                    digest.create_bundle(@bundle)
                else
                    trans = digest.transportable
                    puts trans.to_manifest
                end
                return 0
            end
        end
    end

end

require 'cft/commands/pack'
