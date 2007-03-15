require 'pathname'
require 'etc'

class Cft::Commands::Base
    newcommand(:pack) do
        doc "Pack a raw session into a tar ball"
        
        def opts
            opts = super("cft pack [options] SESSION")
            opts.separator "Pack a raw session into a tarball"
            opts.on("-t", "--tar FILE", 
                    "pack the raw session into FILE") do |val|
                @tarball = val
            end
            opts
        end
        
        require_session :active => "Can't pack an active session",
        :missing => "Could not find session"
        
        def execute(session, args)
            unless @tarball
                $stderr.puts "You must specify the name of the tarball to create"
                $stderr.puts opts
                return 1
            end
            spath = session.path
            %x{tar -czf #{@tarball} -C #{File::dirname(spath)} #{File::basename(spath)} 2>&1}
            unless $?.success?
                $stderr.puts "Failed to create #{@tarball}: #{$?.exitstatus}"
            end
            return $?.exitstatus
        end
    end
end
