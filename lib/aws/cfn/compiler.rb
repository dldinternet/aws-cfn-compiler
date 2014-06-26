require "aws/cfn/compiler/version"

require 'json'
require 'ap'
require 'yaml'
require 'slop'

module Aws
  module Cfn
    module Compiler
      class Main
        attr_accessor :items
        attr_accessor :opts
        attr_accessor :spec

        def initialize
          @items = {}
        end

        def run

          @opts = Slop.parse(help: true) do
            on :d, :directory=, 'The directory to look in', as: String
            on :o, :output=, 'The JSON file to output', as: String
            on :s, :specification=, 'The specification to use when selecting components. A JSON or YAML file or JSON object', as: String
            on :f, :formatversion=, 'The AWS Template format version. Default 2010-09-09', as: String
            on :t, :description=, "The AWS Template description. Default: output basename or #{File.basename(__FILE__,'.rb')}", as: String
          end

          unless @opts[:directory]
            puts @opts
            exit
          end

          load @opts[:specification]

          desc = @opts[:output] ? File.basename(@opts[:output]).gsub(%r/\.(json|yaml)/, '') : File.basename(__FILE__,'.rb')
          if @spec and @spec['Description']
            desc = @spec['Description']
          end
          vers = '2010-09-09'
          if @spec and @spec['AWSTemplateFormatVersion']
            vers = @spec['AWSTemplateFormatVersion']
          end
          # noinspection RubyStringKeysInHashInspection
          compiled = {
              'AWSTemplateFormatVersion' => (@opts[:formatversion].nil? ? vers : @opts[:formatversion]),
              'Description'              => (@opts[:description].nil? ? desc : @opts[:description]),
              'Mappings'                 => @items['Mappings'],
              'Parameters'               => @items['Parameters'],
              'Resources'                => @items['Resources'],
              'Outputs'                  => @items['Outputs'],
          }

          puts
          puts 'Validating compiled file...'

          validate(compiled)

          output_file = @opts[:output] || 'compiled.json'
          puts
          puts "Writing compiled file to #{output_file}..."
          save(compiled, output_file)

          puts
          puts '*** Compiled Successfully ***'
        end

        def validate(compiled)
          raise 'No Resources!?' unless compiled['Resources']

          # Mappings => Resources
          maps  = find_maps(compiled) #.select { |a| !(a =~ /^AWS::/) }
          rscs  = compiled['Resources'].keys
          mpgs  = compiled['Mappings'].nil? ? [] : compiled['Mappings'].keys
          names = rscs+mpgs

          unless (maps-names).empty?
            puts '!!! Unknown mappings !!!'
            (maps-names).each do |name|
              puts "  #{name}"
            end
            abort!
          end
          puts '  Mappings validated'

          # Parameters => Resources => Outputs
          refs  = find_refs(compiled).select { |a,_| !(a =~ /^AWS::/) }
          prms  = compiled['Parameters'].keys rescue []
          # outs  = compiled['Outputs'].keys rescue []
          names = rscs+prms

          unless (refs.keys-names).empty?
            puts '!!! Unknown references !!!'
            (refs.keys-names).each do |name|
              puts "  #{name} from #{refs[name][0]}:#{refs[name][1]}"
            end
            abort!
          end
          puts '  References validated'
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
            puts '  Compiled file written.'
          rescue
            puts "!!! Could not write compiled file: #{$!}"
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

              puts "Loading specification #{abs}..."
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
          end
          %w( Mappings Parameters Resources Outputs ).each do |dir|
            load_dir(dir,@spec)
          end
        end

        protected

        def abort!
          puts '!!! Aborting !!!'
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

        def load_dir(dir,spec=nil)
          puts "Loading #{dir}..."
          raise "No such directory: #{@opts[:directory]}" unless File.directory?(@opts[:directory])
          set = []
          if File.directory?(File.join(@opts[:directory], dir))
            @items[dir] = {}
            set = get_file_set(dir)
          else
            if File.directory?(File.join(@opts[:directory], dir.downcase))
              @items[dir] = {}
              set = get_file_set(dir.downcase)
            end
          end
          set.collect do |filename|
            next unless filename =~ /\.(json|ya?ml)\z/i
            if spec and spec.has_key?(dir)
              base = File.basename(filename).gsub(%r/\.(rb|yaml)/, '')
              next     if spec[dir].nil? # Edge case ... explicitly want NONE of these!
              next unless spec[dir].include?(base)
              puts "\tUsing #{dir}/#{base}"
            end
            begin
              puts "  reading #{filename}"
              content = File.read(filename)
              next if content.size==0

              if filename =~ /\.json\z/i
                item = JSON.parse(content)
              elsif filename =~ /\.ya?ml\z/i
                item = YAML.load(content)
              else
                next
              end
              item.keys.each { |key| raise "Duplicate item: #{key}" if @items[dir].has_key?(key) }
              @items[dir].merge! item
            rescue
              puts "  !! error: #{$!}"
              abort!
            end
          end
          if spec and spec[dir]
            raise "Suspect that a #{dir} item was missed! \nRequested: #{spec[dir]}\n    Found: #{@items[dir].keys}" unless (@items[dir].keys.count == spec[dir].count)
          end
        end

        def get_file_set(dir)
          Dir[File.join(@opts[:directory], "#{dir}.*")] | Dir[File.join(@opts[:directory], dir.to_s, "**", "*")]
        end

      end
    end
  end
end
