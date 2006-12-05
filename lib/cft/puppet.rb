require 'puppet'

module Cft::Puppet
    def self.transportable(session)
        filetype = Puppet::Type.type(:file)
        result = Puppet::TransBucket.new
        result.keyword = "class"
        result.type = session.name
        session.changes.paths.each do |p,c|
            next if Cft::FILTERS.any? { |f| File::fnmatch(f, p) }
            Cft::Puppet::Digest::digesters.each do |ana|
                if ana.digest?(p)
                    trans = ana.transportable(session, p)
                    result.push(trans) if trans
                end
            end
        end
        result
    end
end

require 'cft/puppet/digest.rb'
