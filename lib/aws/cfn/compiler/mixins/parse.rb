require 'rubygems/dependency'
require 'semverse'
require 'awesome_print'
require 'aws/cfn/dsl/version'
require 'aws/cfn/decompiler/version'

module Aws
  module Cfn
    module Compiler
      module Parse

        def parse
          parse_meta(@spec)
          @dsl ||= Aws::Cfn::Dsl::Template.new(@config[:directory])
          @all_sections.each do |section|
            parse_section(section,@spec)
          end
        end

        def parse_meta(spec)
          begin
            reqs = meta(:Require)
            if reqs
              reqs.each do |name,args|
                requirement(name,args)
              end
            end
          rescue Exception => e
            abort! e
          end
        end

        def requirement(name, *args)

          #options = args.last.is_a?(Hash) ? args.pop.dup : {}
          constraint = case args.class.name
                         when /Array/
                           args.shift
                         when /Symbol/
                           args.to_s
                         when /String/
                           args
                         else
                           raise "Unsupported class #{args.class.name} for #{args.ai}"
                       end
          version,constraint = case name
            when /Compiler/
              [Aws::Cfn::Compiler::VERSION,constraint]
            when /^(DeCompiler|Decompiler)/
              [Aws::Cfn::DeCompiler::VERSION,constraint]
            when /^(Dsl|DSL)/
              [Aws::Cfn::Dsl::VERSION,constraint]
            when /Gems/
              constraint.map { |h|
                h.map { |k,v|
                  ver = eval "#{k}::VERSION"
                  semver = ::Semverse::Version.new(ver)
                  raise "The constraint failed: #{k} #{v} (Found #{ver})" unless ::Semverse::Constraint.new(v).satisfies?(semver)
                }
              }
              return
            when /Template/
              @logger.warn "Template constraint check supported but not implemented in version #{VERSION}: #{constraint}"
              return
            # when /MinVersion/
            #   [Aws::Cfn::Compiler::VERSION,">= #{constraint}"]
            else
              raise "#{name} constraint not supported"
          end

          raise "The constraint failed: #{name} #{constraint} (Found #{version})" unless ::Semverse::Constraint.new(constraint).satisfies?(::Semverse::Version.new(version))

        end

        # noinspection RubyGlobalVariableNamingConvention
        def parse_section(section,spec=nil)
          logStep "Parsing #{section}..."

          if spec and spec[section]
            @items          ||= {}
            @items[section] ||= {}
            @dynamic_items[section] ||= {}
            get  = {}
            spec[section].each do |rsrc|
              item = {}
              item[section] ||= {}
              @logger.debug "\tUsing #{section}::#{rsrc}"
              refp,sub,base,rel = map_resource_reference(rsrc)
              if refp.nil?
                path = get_brick_dirname(section, rsrc)
              else
                path = get_brick_dirname(sub ? sub : section, rsrc, refp, rel)
              end
              abort! "No such directory: #{path} (I am here: #{Dir.pwd})" unless File.directory?(path)
              unless get[path]
                get[path] = get_file_set([".*"], path, @config[:precedence])
              end
              set = get[path]
              if set[base]
                if item[section].has_key?(base)
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
                    # Ruby bricks can now define resources across section boundaries!
                    item = parse_rb_file(base, section, filename)
                  elsif filename =~ /\.js(|on)\z/i
                    item[section].merge! JSON.parse(content)
                  elsif filename =~ /\.ya?ml\z/i
                    begin
                      item[section].merge! YAML.load(content) # item[section].merge! YAML.safe_load(content) #
                    rescue => e
                      logger.fatal "YAML error: #{e.message}"
                      raise e
                    end
                  else
                    next
                  end

                  unless item[section].has_key?(base)
                    filn = if @config[:expandedpaths]
                             filename
                           else
                             short_path(filename,2)
                           end
                    @logger.error "  !! error: Brick in #{filn} does not define #{section}/#{base}!?\nIt defines these: #{item[section].keys}"
                    abort!
                  end
                rescue
                  abort! "  !! error: #{$!}"
                end
                item.each { |sect,hash|
                  hash.keys.each do |key|
                    if @items.has_key?(sect)
                      if @items[sect].has_key?(key)
                        abort! "  !! error: Duplicate item: #{sect}/#{key}"
                      end
                    else
                      @items[sect] ||= {}
                    end
                  end
                  @items[sect].merge! hash
                }
              else
                pm = []
                set.map { |r,f|
                  b = File.basename(f).gsub( %r(\..*?$), '' )
                  pm << b if b.downcase == rsrc.downcase
                }
                abort! "  !! error: #{section}/#{base} not found! Possible matches: #{pm}"
              end
            end

            unless @items[section].keys.count == (spec[section].count + @dynamic_items[section].keys.count)
              @logger.error "#{section} section check failed! \nRequested: #{spec[section]}\n    Found: #{@items[section].keys}\n  Dynamic: #{@dynamic_items[section].keys}\n"+
                            "  !! Suspect that a #{section} item was missed, duplicated or not properly named (Brick name and file name mismatch?)!"
              @dynamic_items[section].each do |k,_|
                if @items.has_key?(k)
                  @logger.error "Dynamic #{section}/#{k} duplicates a static resource!"
                end
              end
              abort! 'Cannot continue'
            end
          end

        end

        def parse_rb_file(base, section, filename)
          Aws::Cfn::Compiler.binding                ||= {}
          Aws::Cfn::Compiler.binding[section]       ||= {}
          Aws::Cfn::Compiler.binding[section][base] ||= {
              :brick_path      => @config[:brick_path],
              :brick_path_list => @config[:brick_path_list],
              :template        => @dsl,
              :logger          => @logger,
              :compiler        => self
          }
          source_file = File.expand_path(filename)
          begin
            eval 'require source_file', binding
          rescue Exception => e
            abort! "Cannot compile #{source_file}\n\n" + e.message + "\n\n" + e.backtrace.to_s
          end
          unless @dsl.dict[section.to_sym]
            abort! "Unable to compile/expand #{filename} for #{section}/#{base}.\n(No #{section} were created?!)"
          end
          dict = sym_to_s(@dsl.dict)
          @dsl = Aws::Cfn::Dsl::Template.new(@config[:directory])
          dict
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
            when /Symbol/
              hash.to_s
            else
              abort! "Internal error: #{hash} is a #{hash.class.name} which our Ruby parsing is not prepared for. Fix #{__FILE__}::sym_to_s"
          end
        end

      end
    end
  end
end
