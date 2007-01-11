require 'etc'

module Cft::Puppet

    class Digest
        attr_reader :session, :bucket

        def initialize(session)
            @session = session
        end

        def before
            if @before.nil?
                @before = @session.trans(:before)
            end
            @before
        end

        def after
            if @after.nil?
                @after = @session.trans(:after)
            end
            @after
        end

        def obj_seen?(type, name)
            before.find_obj(type, name) ||
                after.find_obj(type, name)
        end

        def diff
            result = Puppet::TransBucket.new
            result.keyword = :manifest
            result.type = "diff"
            before.each_obj do |bto|
                ato = after.find_obj(bto.type, bto.name)
                if ato.nil?
                    # Object was deleted
                    to = Puppet::TransObject.new(bto.name, bto.type)
                    to[:ensure] = :absent
                    result << to
                elsif ato.any? { |p, v| ato[p] != bto[p] }
                    # At least one param was changed
                    result << ato
                end
            end
            after.each_obj do |ato|
                bto = before.find_obj(ato.type, ato.name)
                if bto.nil?
                    # Object was added
                    result << ato
                end
            end
            return result
        end

        def transportable
            @bucket = diff
            @bucket.keyword = "class"
            @bucket.type = @session.name
            @session.changes.paths.each do |p,c|
                next if Cft::FILTERS.any? { |f| File::fnmatch(f, p) }
                dig = Cft::Puppet::Digest::find(p)
                dig.transportable(self, p)
            end
            return @bucket
        end

        # Create a bundle (tarball) of the manifest and all needed files
        # for +session+ The tarball will be put in a file named +fname+
        def create_bundle(fname)
            bpath = @session.path(:bundle)
            if File::exists?(bpath)
                system("rm -rf #{bpath}")
            end
            FileUtils::mkdir_p(bpath)
            trans = transportable
            trans.each_obj do |f|
                if f.type == :file
                    src = f[:source]
                    tgt = File::join(bpath, File::basename(src))
                    FileUtils::cp_r(src, tgt)
                    # FIXME: What if file names from different file elements
                    # conflict ?
                    f[:source] = File::basename(src)
                end
            end
            File::open(File::join(bpath, "manifest.pp"), "w") do |f|
                f.puts(trans.to_manifest)
            end
            %x{tar -czf #{fname} -C #{File::join(bpath, "..")} #{File::basename(bpath)} 2>&1}
            unless $? == 0
                raise Error, "Failed to create #{fname}"
            end
        end


        def self.digester(name, &block)
            @digesters ||= []
            # Be very careful: order is important
            @digesters.unshift(Base::new(name, &block))
        end

        def self.find(path)
            result = @digesters.find { |dig| dig.digest?(path) }
            unless result
                raise InternalError, "No digester for #{path}"
            end
            return result
        end

        def self.digesters
            @digesters
        end

        class Base
            attr_reader :typnam
            @@glob_cnt = 0

            def initialize(typnam, &block)
                @typnam = typnam
                @preserve = false
                @globs = {}
                yield(self)
            end
            
            def preserve
                @preserve = true
            end

            def preserve?
                @preserve
            end

            # Digester handles PATTERNS; actual handling is done by the BLOCK
            # which is called with the digester and the matching path
            def glob(*patterns, &block)
                @@glob_cnt += 1
                name = "glob#{@@glob_cnt}".intern
                self.class.define_method(name, &block)
                patterns.each do |p| 
                    @globs[p] = name
                end
            end

            # Indicate that PATTERNS is handled by the digester, but
            # don't do anything for them
            def ignore(*patterns)
                patterns.each do |p|
                    @globs[p] = :glob_ignore
                end
            end
            
            def type
                Puppet::Type.type(@typnam)
            end

            def digest?(path)
                @globs.keys.any? { |d| File::fnmatch(d, path) }
            end

            def transportable(digest, path)
                @globs.keys.select { |pat|
                    File::fnmatch(pat, path)
                }.each { |pat|
                    self.send(@globs[pat], digest, path)
                }
            end

            def scrub_attr!(trans)
                type.eachattr do |attr, kind|
                    trans.delete(attr.name) if kind != :state
                end
                trans
            end

            private
            # Used as the filter for ignored globs
            def glob_ignore(d,p)
            end
        end

        digester(:file) do |d|

            def d.skipstate?(name)
                [:source, :content, :checksum, :target].include?(name)
            end

            d.glob "*" do |digest, path|
                trans = nil
                if digest.session.changes.exist?(path)
                    # Dealing with :source is a PITA; setting it too early
                    # confuses puppet enormously
                    obj = type.create({ :name => digest.session.source(path) })
                
                    type.validstates.each { |n|
                        unless skipstate?(n) || obj.should(n)
                            obj.newstate(n)
                        end
                    }
                    obj.retrieve
                    trans = obj.to_trans
                    trans[:source] = trans.name
                    trans.name = path
                    trans[:group] = gid_to_s(trans[:group])
                    trans[:owner] = uid_to_s(trans[:owner])
                    trans[:mode] = mode_to_s(trans[:mode])
                else
                    # PATH was deleted
                    c = digest.session.changes.paths[path]
                    if c[0] == Cft::CREATED
                        # Ignore files that were created and 
                        # deleted in this session
                        return nil
                    end
                    trans = type.create({
                      :name => path,
                      :ensure => :absent
                    }).to_trans
                end
                if trans
                    scrub_attr!(trans)
                end
                digest.bucket << trans
            end

            private
            # FIXME: Try and use the existing user providers for this
            def d.gid_to_s(gid)
                begin
                    Etc.getgrgid(gid).name
                rescue ArgumentError
                    gid.to_s
                end
            end

            def d.uid_to_s(uid)
                begin
                    Etc.getpwuid(uid).name
                rescue ArgumentError
                    uid.to_s
                end
            end

            def d.mode_to_s(m)
                if m.is_a?(Integer)
                    "0" + m.to_s(8)
                else
                    m
                end
            end

        end

        digester(:service) do |d|
            d.preserve

            # Use the subsys files to get a better idea of whether a
            # service is still running or not, but don't create service
            # entries based on subsys files, since they could be part of
            # a bigger demon
            d.glob "/var/lock/subsys/*" do |digest, path|
                svc = File::basename(path)
                if digest.obj_seen?(typnam, svc)
                    state = digest.session.changes.paths[path].reverse.find do |c| 
                        c != Cft::CHANGED
                    end
                    ens = (state == Cft::CREATED) ? "running" : "stopped"
                    trans = digest.bucket.get_obj(typnam, svc, :ensure => ens)
                end
            end

            d.ignore "/etc/rc?.d/*", "/etc/rc.d/rc?.d/*"
        end

        digester(:user) do |d|
            d.preserve
            
            d.ignore "/etc/passwd", "/etc/passwd-"
            d.ignore "/etc/shadow", "/etc/shadow-"
        end

        digester(:group) do |d|
            d.preserve

            d.ignore "/etc/group", "/etc/group-"
            d.ignore "/etc/gshadow", "/etc/gshadow-"
        end

        digester(:yumrepo) do |d|
            d.preserve
            
            # In theory, yum.conf can contain repos, too
            d.ignore "/etc/yum.repos.d/*.repo"
            d.ignore "/etc/yum/repos.d/*.repo"
            
        end
    end
end
