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
                when :DescriptionString
                  "#{meta(:Description)} - #{meta(:Name)} v#{meta(:Version)}; Parents: #{meta(:DependsOn)} [Compiled with #{meta(:Compiler,:Name)} v#{meta(:Compiler,:Version)}]"
                else
                  get_meta(spec, args.to_s)
              end
            elsif args.is_a?(String)
              if spec[args]
                spec[args]
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

          begin
            if desc.match(%r'#\{.+?\}')
              eval %(desc = "#{desc}")
            end
          rescue
            # noop
          end
          # ap meta(:Version)
          # ap meta(:Compiler,:Name)
          # ap meta(:Compiler,:Version)

          vers =  if @config[:formatversion]
                    @config[:formatversion]
                  else
                    if @spec and @spec['AWSTemplateFormatVersion']
                      @spec['AWSTemplateFormatVersion']
                    else
                      '2010-09-09'
                    end
                  end
          # [2014-06-29 Christo] IIRC it is important that the section names be strings instead of symbols ...
          # noinspection RubyStringKeysInHashInspection
          compiled =
          {
              'AWSTemplateFormatVersion' => vers,
              'Description'              => desc,
              'Mappings'                 => @items['Mappings'],
              'Parameters'               => @items['Parameters'],
              'Resources'                => @items['Resources'],
              'Outputs'                  => @items['Outputs'],
          }
        end

        def find_refs(hash, type='Reference', parent='')
          h = {}
          newparent = parent
          if hash.is_a? Hash
            hash.keys.collect do |key|
              if %w{Mappings Parameters Resources Outputs}.include? key
                type = key#.gsub(/s$/, '')
                newparent = key
              elsif %w{Mappings Parameters Resources Outputs}.include? parent
                newparent = key
              end
              if %w{Ref}.include? key
                h = { hash[key] => [type,newparent] }
              elsif 'Fn::GetAtt' == key
                h = { hash[key].first => [type,newparent] }
                # elsif %w{SourceSecurityGroupName CacheSecurityGroupNames SecurityGroupNames}.include? key
                #   a = find_refs(hash[key],type,newparent)
                #   h = merge(h, a, *[type,newparent])
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

        def find_maps(hash)
          if hash.is_a? Hash
            tr = []
            hash.keys.collect do |key|
              if 'Fn::FindInMap' == key
                hash[key].first
              else
                find_maps(hash[key])
              end
            end.flatten.compact.uniq
          elsif hash.is_a? Array
            hash.collect{|a| find_maps(a)}.flatten.compact.uniq
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
              @config[:brick_path_list].each do |p|
                path = File.join(p,subm[1]) # File.dirname(@config[:directory])
                unless File.directory?(path)
                  path = nil
                end
              end
              sub = subm[2]
            else
              # sub = nil
              # path = File.join(File.dirname(@config[:directory]),match[1])
              @config[:brick_path_list].each do |p|
                path = File.join(p,match[1]) # File.dirname(@config[:directory])
                unless File.directory?(path)
                  path = nil
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
