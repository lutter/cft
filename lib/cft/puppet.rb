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
        # FIXME: The keys are all symbols here, but when puppet parses a
        # manifest, keys are strings
        result
    end

    def self.genstate(fname)
        result = Puppet::TransBucket.new
        Cft::Puppet::Digest::digesters.select { |dig|
            dig.preserve? 
        }.each { |dig|
            type = dig.type
            bucket = Puppet::TransBucket.new
            bucket.keyword = "class"
            bucket.type = type.name
            type.list.each do |elt|
                bucket.push(elt.to_trans)
            end
            result.push(bucket)
        }
        File::open(fname, "w") do |f|
            f.write(YAML::dump(result))
        end
        return result
    end
end

require 'cft/puppet/digest.rb'
