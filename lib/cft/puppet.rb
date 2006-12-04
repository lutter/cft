require 'puppet'
require 'etc'

module Cft::Puppet
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

    def self.transportable(session)
        filetype = Puppet::Type.type(:file)
        result = Puppet::TransBucket.new
        result.keyword = "class"
        result.type = session.name
        session.changes.paths.each do |p,c|
            if session.changes.exist?(p)
                # Dealing with :source is a PITA; setting it too early
                # confuses puppet enormously
                fileobj = filetype.create({ 
                  :name => session.source(p)
                })
                
                filetype.validstates.each { |n|
                    unless [:source, :content, :checksum].include?(n) || fileobj.should(n)
                        fileobj.newstate(n)
                    end
                }
                fileobj.retrieve
                trans = fileobj.to_trans
                trans[:source] = trans.name
                trans.name = p
                filetype.eachattr do |attr, kind|
                    trans.delete(attr.name) if kind != :state
                end
                trans[:group] = gid_to_s(trans[:group])
                trans[:owner] = uid_to_s(trans[:owner])
                trans[:mode] = mode_to_s(trans[:mode])
                result.push trans
            end
        end
        result
    end
end
