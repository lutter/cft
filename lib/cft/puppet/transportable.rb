# Enhancements for Puppet's TransObject/TransBucket

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
            type = type.to_s.downcase
            flatten.find { |to| to.type.to_s == type && to.name == name }
        end

        def find_all(type)
            type = type.to_s.downcase
            flatten.select { |to| to.type.to_s == type }
        end

        def get_obj(type, name, params = {})
            obj = find_obj(type, name)
            unless obj
                obj = TransObject.new(name, type)
                self << obj
            end
            params.each { |k,v| obj[k] = v }
            return obj
        end

    end
end

module Cft
    # Alias puppet's transportables
    TransBucket = ::Puppet::TransBucket
    TransObject = ::Puppet::TransObject
end
