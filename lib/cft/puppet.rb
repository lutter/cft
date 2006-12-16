require 'puppet'

module Puppet
    class TransObject
        def label
            "#{type}[#{name}]"
        end
    end

    class TransBucket

        def delete_obj(type, name)
            c = @children.find { |c| c.type == type && c.name == name }
            if c.nil?
                @children.each do |c|
                    if c.is_a? self.class
                        c.delete_obj(type,name)
                    end
                end
            else
                @children.delete(c)
            end
        end

        def each_obj
            flatten.each { |to| yield(to) }
        end

        def find_obj(type, name)
            flatten.find { |to| to.type == type && to.name == name }
        end
    end
end

module Cft::Puppet
    def self.diff(before, after)
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

    def self.transportable(session)
        result = Puppet::TransBucket.new
        result.keyword = "class"
        result.type = session.name
        session.changes.paths.each do |p,c|
            next if Cft::FILTERS.any? { |f| File::fnmatch(f, p) }
            dig = Cft::Puppet::Digest::find(p)
            dig.transportable(session, p).each do |to|
                result << to
            end
        end
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
