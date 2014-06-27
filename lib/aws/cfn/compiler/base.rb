
require 'json'
require 'ap'
require 'yaml'
require 'slop'
require 'aws/cfn/dsl/template'

module Aws
  module Cfn
    module Compiler
      class Base
        attr_accessor :items
        attr_accessor :opts
        attr_accessor :spec

        require 'dldinternet/mixlib/logging'
        include DLDInternet::Mixlib::Logging

        def initialize
          @items = {}
          @config ||= {}
          @config[:log_opts] = lambda{|mlll| {
                                      :pattern      => "%#{mlll}l: %m %C\n",
                                      :date_pattern => '%Y-%m-%d %H:%M:%S',
                                    }
                                  }
          @config[:log_level] = :step
          @logger = getLogger(@config)
        end

        def validate(compiled)
          raise 'No Resources!?' unless compiled['Resources']

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
          @logger.step '  Mappings validated'

          # Parameters => Resources => Out@logger.step
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
          @logger.step '  References validated'
        end

        def save(compiled, output_file)
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
            @logger.step '  Compiled file written.'
          rescue
            @logger.error "!!! Could not write compiled file: #{$!}"
            abort!
          end
        end

        def load(spec=nil)
          if spec
            begin
              abs = File.absolute_path(File.expand_path(spec))
              unless File.exists?(abs)
                abs = File.absolute_path(File.expand_path(File.join(@opts[:directory],spec)))
              end
            rescue
              # pass
            end
            if File.exists?(abs)
              raise "Unsupported specification file type: #{spec}=>#{abs}\n\tSupported types are: json,yaml,jts,yts\n" unless abs =~ /\.(json|ya?ml|jts|yts)\z/i

              @logger.step "Loading specification #{abs}..."
              spec = File.read(abs)

              case File.extname(File.basename(abs)).downcase
                when /json|jts/
                  @spec = JSON.parse(spec)
                when /yaml|yts/
                  @spec = YAML.load(spec)
                else
                  raise "Unsupported file type for specification: #{spec}"
              end
              # @spec = spec
            else
              raise "Unable to open specification: #{abs}"
            end
            @dsl ||= Aws::Cfn::Dsl::Template.new(@opts[:directory])
            %w( Mappings Parameters Resources Outputs ).each do |dir|
              load_dir(dir,@spec)
            end
          else
            raise "No specification provided"
          end
        end

        protected

        def abort!
          @logger.fatal '!!! Aborting !!!'
          exit
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
          # Dir[File.join(@opts[:directory], "#{dir}.*")] | Dir[File.join(@opts[:directory], dir.to_s, "**", "*")]
          raise "Bad call to #{self.class.name}.getPathSet: want == nil" unless want
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
            raise ChopError.new "The regular expression attempting to match resources in '#{path}' is incorrect! #{e.message}"
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
                @logger.warn "Ignoring #{File.basename(res[n])}" if res[n]
                res[n] = f
              }
            else
              @logger.info "'#{e}' set is empty! (No #{path}/*.#{e} files found using precedence #{exts})"
            end
          }
          set = res
        end

        def load_dir(dir,spec=nil)
          logStep "Loading #{dir}..."

          if spec and spec[dir]
            raise "No such directory: #{@opts[:directory]}" unless File.directory?(@opts[:directory])
            set = []
            if File.directory?(File.join(@opts[:directory], dir))
              @items[dir] = {}
              set = get_file_set([".*"], "#{@opts[:directory]}/#{dir}", @config[:precedence])
            else
              if File.directory?(File.join(@opts[:directory], dir.downcase))
                @items[dir] = {}
                set = get_file_set(['.*'], dir.downcase, @config[:precedence])
              else
                @logger.error "  !! error: Cannot load bricks from #{File.join(@opts[:directory], dir)}"
                abort!
              end
            end

            item = {}
            spec[dir].each do |base|
              @logger.info "\tUsing #{dir}/#{base}"
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
                  @logger.step "  reading #{filename}"
                  content = File.read(filename)
                  next if content.size==0

                  if filename =~ /\.(rb|ruby)\z/i
                    eval "@dsl.#{content.gsub(%r'^\s+','')}"
                    unless @dsl.dict[dir.to_sym]
                      raise "Unable to expand #{filename} for #{dir}/#{base}"
                    end
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

      end
    end
  end
end
