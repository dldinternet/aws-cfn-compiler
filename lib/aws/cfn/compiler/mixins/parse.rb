module Aws
  module Cfn
    module Compiler
      module Parse

        def parse
          @dsl ||= Aws::Cfn::Dsl::Template.new(@config[:directory])
          %w( Mappings Parameters Resources Outputs ).each do |section|
            parse_section(section,@spec)
          end
        end

        # noinspection RubyGlobalVariableNamingConvention
        def parse_section(section,spec=nil)
          logStep "Parsing #{section}..."

          if spec and spec[section]
            abort! "No such directory: #{@config[:directory]} (I am here: #{Dir.pwd})" unless File.directory?(@config[:directory])
            @items          ||= {}
            @items[section] ||= {}
            get  = {}
            item = {}
            spec[section].each do |rsrc|
              @logger.info "\tUsing #{section}::#{rsrc}"
              refp,sub,base,rel = map_resource_reference(rsrc)
              if refp.nil?
                path = vet_path(section)
              else
                path = vet_path(sub ? sub : section, refp, rel)
              end
              unless get[path]
                get[path] = get_file_set([".*"], path, @config[:precedence])
              end
              set = get[path]
              if set[base]
                if item.has_key?(base)
                  @logger.error "  !! error: Duplicate item: #{section}/#{base}"
                  abort!
                end

                filename = set[base]
                unless filename =~ /\.(ru?by?|ya?ml|js(|on))\z/i
                  @logger.info "Brick not supported/ relevant: #{filename}"
                  next
                end

                begin
                  @logger.debug "  reading #{filename}"
                  content = File.read(filename)
                  next if content.size==0

                  if filename =~ /\.(rb|ruby)\z/i
                    compile_rb_file(base, section, filename)
                    item.merge! @dsl.dict[section.to_sym]
                  elsif filename =~ /\.js(|on)\z/i
                    item.merge! JSON.parse(content)
                  elsif filename =~ /\.ya?ml\z/i
                    item.merge! YAML.load(content)
                  else
                    next
                  end

                rescue
                  abort! "  !! error: #{$!}"
                end
              else
                abort! "  !! error: #{section}/#{base} not found!"
              end
            end
            item.keys.each { |key|
              if @items[section].has_key?(key)
                abort! "  !! error: Duplicate item: #{section}/#{key}"
              end
            }
            @items[section].merge! item

            unless @items[section].keys.count == spec[section].count
              abort! "  !! error: Suspect that a #{section} item was missed! \nRequested: #{spec[section]}\n    Found: #{@items[section].keys}"
            end
          end

        end

      end
    end
  end
end
