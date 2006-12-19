require 'etc'

module Cft::Puppet

    class Digest

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

        def diff
            result = Puppet::TransBucket.new
            result.keyword = :manifest
            result.type = "diff"
            @before.each_obj do |bto|
                ato = @after.find_obj(bto.type, bto.name)
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
            @after.each_obj do |ato|
                bto = @before.find_obj(ato.type, ato.name)
                if bto.nil?
                    # Object was added
                    result << ato
                end
            end
            return result
        end

        def transportable
            result = Puppet::TransBucket.new
            result.keyword = "class"
            result.type = @session.name
            @session.changes.paths.each do |p,c|
                next if Cft::FILTERS.any? { |f| File::fnmatch(f, p) }
                dig = Cft::Puppet::Digest::find(p)
                dig.transportable(@session, p).each do |to|
                    result << to
                end
            end
            result
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

            def glob(*patterns, &block)
                @@glob_cnt += 1
                name = "glob#{@@glob_cnt}".intern
                self.class.define_method(name, &block)
                patterns.each do |p| 
                    @globs[p] = name
                end
            end
            
            def type
                Puppet::Type.type(@typnam)
            end

            def digest?(path)
                @globs.keys.any? { |d| File::fnmatch(d, path) }
            end

            def transportable(session, path)
                @globs.keys.select { |pat|
                    File::fnmatch(pat, path)
                }.map { |pat|
                    self.send(@globs[pat], session, path)
                }.reject { |to| to.nil? }
            end

            def scrub_attr!(trans)
                type.eachattr do |attr, kind|
                    trans.delete(attr.name) if kind != :state
                end
                trans
            end

            def mktrans(name, params)
                to = Puppet::TransObject.new(name, typnam)
                params.each { |k,v| to[k] = v }
                return to
            end
        end

        digester(:file) do |d|

            def d.skipstate?(name)
                [:source, :content, :checksum, :target].include?(name)
            end

            d.glob "*" do |session, path|
                trans = nil
                if session.changes.exist?(path)
                    # Dealing with :source is a PITA; setting it too early
                    # confuses puppet enormously
                    obj = type.create({ :name => session.source(path) })
                
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
                    c = session.changes.paths[path]
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
                return trans
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
            
            d.glob "/var/lock/subsys/*" do |session, path|
                svc = File::basename(path)
                state = session.changes.paths[path].reverse.find do |c| 
                    c != Cft::CHANGED
                end
                ens = nil
                if state == Cft::CREATED
                    ens = :running
                else
                    ens = :stopped
                end
                trans = mktrans(svc, { :ensure => ens.to_s })
            end

            d.glob "/etc/rc?.d/*", "/etc/rc.d/rc?.d/*" do |session, path|
            end
        end

        digester(:user) do |d|
            d.preserve
            
            d.glob "/etc/passwd" do |session, path|
            end
        end

    end
end
