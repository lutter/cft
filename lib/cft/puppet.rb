require 'puppet'

module Cft::Puppet
    
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
require 'cft/puppet/transportable.rb'
