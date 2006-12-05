require 'etc'

module Cft::Puppet
    module Digest

        class Base
            attr_reader :typnam

            def initialize(typnam, digests)
                @typnam = typnam
                @digests = digests
            end
            
            def type
                Puppet::Type.type(@typnam)
            end

            def digest?(path)
                return true if @digests.nil?
                @digests.any? { |d| File::fnmatch(d, path) }
            end

            def scrub_attr!(trans)
                type.eachattr do |attr, kind|
                    trans.delete(attr.name) if kind != :state
                end
                trans
            end
        end

        class PFile < Base
            def initialize
                super(:file, nil)
            end

            def skipstate?(name)
                [:source, :content, :checksum, :target].include?(name)
            end

            def transportable(session, path)
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
                    trans[:group] = PFile::gid_to_s(trans[:group])
                    trans[:owner] = PFile::uid_to_s(trans[:owner])
                    trans[:mode] = PFile::mode_to_s(trans[:mode])
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
            def self.gid_to_s(gid)
                begin
                    Etc.getgrgid(gid).name
                rescue ArgumentError
                    gid.to_s
                end
            end

            def self.uid_to_s(uid)
                begin
                    Etc.getpwuid(uid).name
                rescue ArgumentError
                    uid.to_s
                end
            end

            def self.mode_to_s(m)
                if m.is_a?(Integer)
                    "0" + m.to_s(8)
                else
                    m
                end
            end

        end    

        class Service < Base
            def initialize
                super(:service, [ "/var/lock/subsys/*" ])
            end
            
            def transportable(session, path)
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
                trans = type.create({
                  :name => svc,
                  :ensure => ens
                }).to_trans
                scrub_attr!(trans)
            end
            
        end

        def self.digesters
            [ Service::new, PFile::new ]
        end

    end
end
