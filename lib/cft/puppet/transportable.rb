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
            flatten.find { |to| to.type == type && to.name == name }
        end
    end
end
