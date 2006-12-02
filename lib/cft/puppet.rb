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
        "0" + m.to_s(8)
    end

    def self.transportable(session)
        ft = Puppet::Type.type(:file)
        result = Puppet::TransBucket.new
        result.top = true
        p ft.validstates
        session.changes.paths.each do |p,c|
            if session.changes.exist?(p)
                # Dealing with :source is a PITA; setting it too early
                # confuses puppet enormously
                pf = ft.create({ 
                  :name => session.source(p)
                })
                
                ft.validstates.each { |n|
                    unless [:source, :content, :checksum].include?(n) || pf.should(n)
                        pf.newstate(n)
                    end
                }
                #p pf.should(:source)
                #pf.eachstate do |s|
                #    p s
                #    s.retrieve
                #    s.should = s.is
                #end
                pf.retrieve
                trans = pf.to_trans
                trans[:source] = trans.name
                trans.name = p
                ft.eachattr do |attr, kind|
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
