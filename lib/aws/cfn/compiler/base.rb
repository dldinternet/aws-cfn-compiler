
require 'json'
require 'ap'
require 'yaml'
require 'slop'
require 'aws/cfn/dsl/base'
require 'aws/cfn/dsl/template'

module Aws
  module Cfn
    module Compiler
      class Base < ::Aws::Cfn::Dsl::Base
        attr_accessor :items
        attr_accessor :opts
        attr_accessor :spec

        def initialize
          super
          @items = {}
        end

        def validate(compiled)
          abort! 'No Resources!?' unless compiled['Resources']
          logStep 'Validating compiled file...'

          # Mappings => Resources
          maps  = find_maps(compiled) #.select { |a| !(a =~ /^AWS::/) }
          rscs  = compiled['Resources'].keys
          mpgs  = compiled['Mappings'].nil? ? [] : compiled['Mappings'].keys
          names = rscs+mpgs

          unless (maps-names).empty?
            @logger.error '!!! Unknown mappings !!!'
            (maps-names).each do |name|
              @logger.error "  #{name}"
            end
            abort!
          end
          @logger.info '  Mappings validated'

          # Parameters => Resources => Outputs
          refs  = find_refs(compiled).select { |a,_| !(a =~ /^AWS::/) }
          prms  = compiled['Parameters'].keys rescue []
          # outs  = compiled['Outputs'].keys rescue []
          names = rscs+prms

          unless (refs.keys-names).empty?
            @logger.error '!!! Unknown references !!!'
            (refs.keys-names).each do |name|
              @logger.error "  #{name} from #{refs[name][0]}:#{refs[name][1]}"
            end
            abort!
          end
          @logger.info '  References validated'
        end

        def save_template(output_file,compiled)
          output_file = File.realpath(File.expand_path(output_file)) if @config[:expandedpaths]
          logStep "Writing compiled file to #{output_file}..."
          begin
            hash = {}
            compiled.each do |item,value|
              unless value.nil?
                if (not value.is_a?(Hash)) or (value.count > 0)
                  hash[item] = value
                end
              end
            end

            File.open output_file, 'w' do |f|
              f.write JSON.pretty_generate(hash, { indent: "\t", space: ' '})
            end
            @logger.info '  Compiled file written.'
          rescue
            @logger.error "!!! Could not write compiled file: #{$!}"
            abort!
          end
        end

        def load_spec(spec=nil)
          if spec
            abs = nil
            [spec, File.join(@config[:directory],spec)].each do |p|
              begin
                abs = File.realpath(File.absolute_path(File.expand_path(p)))
                break if File.exists?(abs)
              rescue => e
                @logger.debug e
                # pass
              end
            end

            if not abs.nil? and File.exists?(abs)
              logStep "Loading specification #{@config[:expandedpaths] ? abs : spec}..."
              unless abs =~ /\.(json|ya?ml|jts|yts)\z/i
                abort! "Unsupported specification file type: #{spec}=>#{abs}\n\tSupported types are: json,yaml,jts,yts\n"
              end

              spec = File.read(abs)

              case File.extname(File.basename(abs)).downcase
                when /json|jts/
                  @spec = JSON.parse(spec)
                when /yaml|yts/
                  @spec = YAML.load(spec)
                else
                  abort! "Unsupported file type for specification: #{spec}"
              end
            else
              abort! "Unable to open specification"+ (abs.nil? ? " or {,#{@config[:directory]}/}#{spec} not found" : ": #{abs}")
            end
            @dsl ||= Aws::Cfn::Dsl::Template.new(@config[:directory])
            %w( Mappings Parameters Resources Outputs ).each do |dir|
              load_dir(dir,@spec)
            end
          else
            raise "No specification provided"
          end
        end

        protected

        # noinspection RubyGlobalVariableNamingConvention
        def load_dir(dir,spec=nil)
          logStep "Loading #{dir}..."

          if spec and spec[dir]
            raise "No such directory: #{@config[:directory]}" unless File.directory?(@config[:directory])
            path = vet_path(dir)
            @items      ||= {}
            @items[dir] ||= {}
            set = {}
            get = {}
            get[path] = get_file_set([".*"], path, @config[:precedence])

            item = {}
            spec[dir].each do |rsrc|
              @logger.info "\tUsing #{dir}::#{rsrc}"
              set = get[path]
              refp,sub,base,rel = map_resource_reference(rsrc)
              unless refp.nil?
                path = vet_path(sub ? sub : dir,refp, rel)
                unless get[path]
                  get[path] = get_file_set([".*"], path, @config[:precedence])
                  set = get[path]
                end
              end
              if set[base]
                if item.has_key?(base)
                  @logger.error "  !! error: Duplicate item: #{dir}/#{base}"
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
                    compile_rb_file(base, dir, filename)
                    item.merge! @dsl.dict[dir.to_sym]
                  elsif filename =~ /\.js(|on)\z/i
                    item.merge! JSON.parse(content)
                  elsif filename =~ /\.ya?ml\z/i
                    item.merge! YAML.load(content)
                  else
                    next
                  end

                rescue
                  @logger.error "  !! error: #{$!}"
                  abort!
                end
              else
                @logger.error "  !! error: #{dir}/#{base} not found!"
                abort!
              end
            end
            item.keys.each { |key|
              if @items[dir].has_key?(key)
                @logger.error "  !! error: Duplicate item: #{dir}/#{key}"
                abort!
              end
            }
            @items[dir].merge! item

            unless @items[dir].keys.count == spec[dir].count
              @logger.error "  !! error: Suspect that a #{dir} item was missed! \nRequested: #{spec[dir]}\n    Found: #{@items[dir].keys}"
              abort!
            end
          end

        end

        def compile_rb_file(base, dir, filename)
          Aws::Cfn::Compiler.binding ||= {}
          Aws::Cfn::Compiler.binding[dir] ||= {}
          Aws::Cfn::Compiler.binding[dir][base] ||= {
              brick_path: @config[:directory],
              template: @dsl,
              logger: @logger
          }
          source_file = File.expand_path(filename)
          # source      = IO.read(source_file)
          eval "require source_file", binding
          unless @dsl.dict[dir.to_sym]
            abort! "Unable to compile/expand #{filename} for #{dir}/#{base}"
          end
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

        # --------------------------------------------------------------------------------
        def get_file_set(want, path, exts=[])
          raise "Bad call to #{self.class.name}.get_file_set: want == nil" unless want
          @logger.debug "Look for #{want.ai} in #{[path]} with #{exts} extensions"
          if exts.nil?
            exts = @config[:precedence]
          end
          file_regex=%r/^(\S+)\.(#{exts.join('|')})$/
          if exts.empty?
            file_regex=%r/^(\S+)()$/
            exts=['']
          end
          regex = "^(#{want.join('|')})$"
          set = {}
          abs = File.expand_path(path)
          abs = path unless @config[:expandedpaths]
          raise "Oops! Does '#{path}' directory exist?" unless File.directory?(abs)
          #abs = File.realpath(abs)
          begin
            Dir.glob("#{abs}/*").each{ |f|
              match = File.basename(f).match(file_regex)
              if match
                name = match[1]
                ext  = match[2]
                set[ext] = {} unless set[ext]
                @logger.trace "#{name} =~ #{regex}"
                set[ext][name] = f if name.match(regex)
              end
            }
          rescue RegexpError => e
            raise "The regular expression attempting to match resources in '#{path}' is incorrect! #{e.message}"
          end
          @logger.debug "getPathSet set=#{set.ai}"
          res = {}
          # Iterate extension sets in increasing precedence order ...
          # Survivor will be the most desireable version of the item
          # i.e. the .rb environment, role, data bag, etc. will be preferred over the .json version
          exts.each{ |e|
            h = set[e]
            if h
              h.each{ |n,f|
                @logger.info "Ignoring #{File.basename(res[n])}" if res[n]
                res[n] = f
              }
            else
              @logger.debug "'#{e}' set is empty! (No #{path}/*.#{e} files found using precedence #{exts})"
            end
          }
          res
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
              path = File.join(File.dirname(@config[:directory]),subm[1])
              sub = subm[2]
            else
              # sub = nil
              path = File.join(File.dirname(@config[:directory]),match[1])
            end
          else
            # Otherwise it is what it seems ;)
            ref  = rsrc
          end
          [path,sub,ref,rel]
        end

        def vet_path(dir,base=nil,rel=false)
          if rel
            base = File.realpath(File.expand_path(File.join(@config[:directory], base)))
          else
            base = @config[:directory] unless base
          end
          path = nil
          [dir, dir.downcase].each do |d|
            path = File.join(base, dir)
            if File.directory?(path)
              break
            end
          end
          unless File.directory?(path)
            @logger.error "  !! error: Cannot load bricks from #{path} (started with #{File.join(base, dir)}')"
            abort!
          end
          path
        end

      end
    end
  end
end
