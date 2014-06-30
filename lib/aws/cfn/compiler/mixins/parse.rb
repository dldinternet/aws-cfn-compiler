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
                    item.merge! parse_rb_file(base, section, filename)
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

        def parse_rb_file(base, section, filename)
          Aws::Cfn::Compiler.binding ||= {}
          Aws::Cfn::Compiler.binding[section] ||= {}
          Aws::Cfn::Compiler.binding[section][base] ||= {
              brick_path: @config[:directory],
              template: @dsl,
              logger: @logger
          }
          source_file = File.expand_path(filename)
          # source      = IO.read(source_file)
          eval "require source_file", binding
          unless @dsl.dict[section.to_sym]
            abort! "Unable to compile/expand #{filename} for #{section}/#{base}"
          end
          sym_to_s(@dsl.dict[section.to_sym])
        end

        def sym_to_s(hash)
          case hash.class.name
          when /Hash/
            item = {}
            hash.each { |k,v|
              item[k.to_s] = sym_to_s(v)
            }
            item
          when /Array/
            hash.map{|e| sym_to_s(e) }
          when /Fixnum|String|TrueClass|FalseClass/
            hash
          else
            abort! "Internal error: #{hash} is a #{hash.class.name} which our Ruby parsing is not prepared for. Fix #{__FILE__}::sym_to_s"
          end
        end

      end
    end
  end
end
