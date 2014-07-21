module Aws
  module Cfn
    module Compiler
      module Compile

        def get_meta(spec,args)

          if spec.is_a?(Hash)
            if args.is_a?(Array)
              args.flatten!
              if args.size > 0
                a = args.shift
                get_meta(get_meta(spec, a), args)
              else
                spec
              end
            elsif args.is_a?(Hash)
              h = {}
              args.map { |e, v| h[e] = get_meta(spec, v) }
              h
            elsif args.is_a?(Symbol)
              # noinspection RubyStringKeysInHashInspection
              case args
                when :Compiler
                  {
                      'Name'    => ::Aws::Cfn::Compiler.name,
                      'Version' => ::Aws::Cfn::Compiler::VERSION,
                  }
                when :Specification
                  File.basename(@config[:specification])
                when :Template
                  File.basename(@config[:template])
                when :DescriptionString
                  v = nil
                  begin
                    dependson = meta(:DependsOn)
                  rescue
                    dependson = []
                  end
                  begin
                    required = meta(:Require)['Template']
                    ok = true
                    required.map { |e| ok = (ok and e.is_a?(Hash)) }
                    if ok
                      required = required.map { |e| e.keys }.flatten
                    else
                      required = nil
                    end
                  rescue
                    required = []
                  end
                  raise "Bad Require:Template: meta-data ...\n#{meta(:Require).ai}. Must resolve to a Hash!\nFor example:\nRequire:\n  Template:\n  - my-template: '>= 0.0.0'" unless required
                  if dependson or required
                    # noinspection RubyHashKeysTypesInspection
                    parents = {}
                    dependson.each { |i| parents[i] = true }
                    required.each { |i| parents[i] = true }
                    parents = "Parents: [#{parents.keys.join(',')}] "
                  else
                    parents = ''
                  end
                  # noinspection RubyExpressionInStringInspection
                  template = '#{meta(:Project,:Description)}(#{meta(:Project,:Name)}) - #{meta(:Name)} v#{meta(:Version)}; #{parents} [Compiled with #{meta(:Compiler,:Name)} v#{meta(:Compiler,:Version)}]'
                  begin
                    eval %(v = "#{template}" )
                  rescue Exception => e
                    raise e.message + "\nIn:\n" + template
                  end
                  v
                else
                  get_meta(spec, args.to_s)
              end
            elsif args.is_a?(String)
              if spec[args]
                spec[args]
              else
                raise "Meta:'#{args}' not set"
              end
            else
              nil
            end
          else
            spec
          end
        end

        def meta(*args)
          if @spec['Meta']
            get_meta(@spec['Meta'],args)
          else
            raise "Specification contained no metadata while expanding #{args}"
          end
        end

        def compile_spec
          desc =  if @config[:description]
                    @config[:description]
                  elsif @spec and @spec['Description']
                    @spec['Description']
                  elsif @config[:template]
                    File.basename(@config[:template]).gsub(%r/\..*$/, '')
                  else
                    'compiled template'
                  end

          vers =  if @config[:formatversion]
                    @config[:formatversion]
                  else
                    if @spec and @spec['AWSTemplateFormatVersion']
                      @spec['AWSTemplateFormatVersion']
                    else
                      '2010-09-09'
                    end
                  end

          desc = compile_value(desc)

          # [2014-06-29 Christo] IIRC it is important that the section names be strings instead of symbols ...
          # noinspection RubyStringKeysInHashInspection
          compiled =
              {
                  'AWSTemplateFormatVersion' => vers,
                  'Description'              => desc,
                  'Mappings'                 => @items['Mappings'],
                  'Parameters'               => @items['Parameters'],
                  'Conditions'               => @items['Conditions'],
                  'Resources'                => @items['Resources'],
                  'Outputs'                  => @items['Outputs'],
              }

          @all_sections.each do |section|
            value = compile_value(@items[section])
            compiled[section] = value if value
          end
          compiled
        end

        def compile_value(expr)
          begin
            if expr.is_a?(Hash)
              val = expr
              expr.each do |k,v|
                val[k] = compile_value(v)
              end
              val
            elsif expr.is_a?(Array)
              expr.map{ |e|
                compile_value(e)
              }
            elsif expr.is_a?(Symbol)
              expr
            elsif expr.is_a?(NilClass)
              expr
            elsif expr.is_a?(TrueClass)
              expr
            elsif expr.is_a?(FalseClass)
              expr
            elsif expr.is_a?(Fixnum)
              expr
            elsif expr.is_a?(String)
              val = expr
              if expr.match(%r'#\{.+?\}')
                eval %(val = "#{expr}")
              end
              val
            else
              raise "The expression type #{expr.class.name} cannot be compiled!\n#{expr}"
            end
          rescue Exception => e
            abort! "Specification expression error: #{e.message} on '#{expr}'"
          end
        end

        def find_refs(hash, type='Reference', parent='')
          h = {}
          newparent = parent
          if hash.is_a? Hash
            hash.keys.collect do |key|
              if @all_sections.include? key
                type = key#.gsub(/s$/, '')
                newparent = key
              elsif @all_sections.include? parent
                newparent = key
              end
              if %w{Ref}.include? key
                h = { hash[key] => [type,newparent] }
              elsif 'Fn::GetAtt' == key
                h = { hash[key].first => [type,newparent] }
              elsif 'DependsOn' == key
                if hash[key].is_a?(Array)
                  h = {}
                  hash[key].map { |dep|
                    h[dep] = [type,newparent]
                  }
                else
                  h = { hash[key] => [type,newparent] }
                end
              else
                a = find_refs(hash[key],type,newparent)
                h = merge(h, a, *[type,newparent])
              end
            end.flatten.compact.uniq
          elsif hash.is_a? Array
            a = hash.map{|i| find_refs(i,type,newparent) }
            h = merge(h, a, type, *[type,newparent])
          end
          h
        end

        def merge(h, a, *type)
          if a.is_a? Hash
            if a.size > 0
              h.merge! a
            end
          else
            a.flatten.compact.uniq.map { |i|
              if i.is_a? Hash
                if i.size > 0
                  h.merge! i
                  h
                end
              else
                h[i] = type
              end
            }
          end
          h
        end

        def find_fns(hash)
          a = []
          if hash.is_a? Hash
            hash.each do |key,val|
              if key.match %r'^Fn::'
                a << key
              end
              a << find_fns(val)
            end
          elsif hash.is_a? Array
            hash.collect{|e|
              a << find_fns(e)
            }
          end
          r = a.flatten.compact.uniq
          r
        end

        def find_maps(hash,source=[])
          if hash.is_a? Hash
            hash.keys.collect do |key|
              if 'Fn::FindInMap' == key
                { mapping: hash[key].first, source: source }
              else
                find_maps(hash[key], [ source, key ].flatten!)
              end
            end.flatten.compact.uniq
          elsif hash.is_a? Array
            hash.collect{|a|
              find_maps(a,source)}.flatten.compact.uniq
          end
        end

        def find_conditions(hash)
          if hash.is_a? Hash
            hash.keys.collect do |key|
              if 'Condition' == key
                if hash[key].is_a?(Array)
                  hash[key].first
                else
                  hash[key]
                end
              else
                find_conditions(hash[key])
              end
            end.flatten.compact.uniq
          elsif hash.is_a? Array
            hash.collect{|a| find_conditions(a)}.flatten.compact.uniq
          end
        end

        def map_resource_reference(rsrc)
          path = nil
          sub  = nil
          ref  = nil
          rel  = false
          # noinspection RubyParenthesesAroundConditionInspection
          if rsrc.match %r'^(\.\./.*?)::(.*)$'
            # Relative path stack reference
            path,sub,ref,rel  = map_resource_reference(File.basename(rsrc))
          elsif rsrc.match %r'^(~/.*?)$'
            # Relative to HOME
            path,sub,ref,rel  = map_resource_reference(File.expand_path(rsrc))
          elsif rsrc.match %r'^(\.\./[^:]*?)$'
            # Relative path
            path = File.dirname(rsrc)
            sub  = File.basename(path)
            path = File.dirname(path)
            ref  = File.basename(rsrc)
            rel  = true
          elsif rsrc.match %r'(^/.*?)::(.*)$'
            # Absolute path
            _,sub,ref,rel  = map_resource_reference(File.basename(rsrc))
            path = File.realpath(File.join(File.dirname(rsrc),_))
          elsif rsrc.match %r'(^/.*?[^:]*?)$'
            # Absolute path
            path = File.dirname(rsrc)
            sub  = File.basename(path)
            path = File.dirname(path)
            ref  = File.basename(rsrc)
          elsif (match = rsrc.match %r'^(.*?)::(.*)$')
            # Inherited stack reference
            ref = match[2]
            # noinspection RubyParenthesesAroundConditionInspection
            if (subm = match[1].match(%r'^(.+?)/(.+)$'))
              # Stack referenced with a path
              @config[:brick_path_list].each do |p|
                path = File.join(p,subm[1]) # File.dirname(@config[:directory])
                if File.directory?(path)
                  break
                else
                  path = nil
                end
              end
              sub = subm[2]
            else
              # Stack referenced on stack_path ...
              pstk = @config[:stack_path_list].map{ |p|
                if File.basename(p) == match[1]
                  p
                else
                  []
                end
              }.flatten.shift
              if pstk
                parseList(@config[:brick_path],':').each do |p|
                  path = File.join(pstk,p) # File.dirname(@config[:directory])
                  if File.directory?(path)
                    break
                  else
                    path = nil
                  end
                end
              end
            end
          else
            # Otherwise it is what it seems ;)
            ref  = rsrc
          end
          [path,sub,ref,rel]
        end


      end
    end
  end
end
