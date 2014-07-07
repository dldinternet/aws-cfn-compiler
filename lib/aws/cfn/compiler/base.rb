
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
          logStep 'Validating template'

          prms  = compiled['Parameters'].keys rescue []
          compiled['Parameters'].each do |name,hash|
            abort! "Parameter #{name} has an invalid compiled block!\n#{hash.ai}" unless hash.is_a?(Hash)
            if hash['Type']
              unless %w(String Number CommaDelimitedList).include?(hash['Type'])
                abort! "Parameter #{name} has an invalid type: #{hash['Type']}"
              end
            end
            if hash['Default']
              unless hash['Default'].is_a?(String)
                abort! "Parameter #{name} has an invalid default (Must be string): #{hash['Default']}"
              end
            end
          end
          @logger.info '  Parameters validated'

          # Mappings => Resources
          funs  = find_fns(compiled) #.select { |a| !(a =~ /^AWS::/) }

          bad = []
          funs.each do |fn|
            unless @valid_functions.include?(fn)
              bad << fn
            end
          end
          if bad.size > 0
            abort! "Encountered unsupported function(s) ...\n#{bad.ai}\nSupported functions are:\n#{@valid_functions.ai}"
          end
          @logger.info '  Functions validated'

          # Mappings => Resources
          maps  = find_maps(compiled) #.select { |a| !(a =~ /^AWS::/) }
          mpgs  = compiled['Mappings'].nil? ? [] : compiled['Mappings'].keys
          names = mpgs # rscs+

          unless (maps-names).empty?
            @logger.error '!!! Unknown mappings !!!'
            (maps-names).each do |name|
              @logger.error "  #{name}"
            end
            abort!
          end
          net = (names-maps)
          unless net.empty?
            @logger.warn '!!! Unused mappings !!!'
            net.each do |name|
              @logger.warn "  #{name}"
            end
          end
          @logger.info '  Mappings validated'

          # Parameters => Resources => Outputs
          refs  = find_refs(compiled).select { |a,_| !(a =~ /^AWS::/) }
          rscs  = compiled['Resources'].keys
          cnds  = compiled['Conditions'].keys rescue []
          # outs  = compiled['Outputs'].keys rescue []
          names = rscs+prms+cnds

          net = (refs.keys-names)
          unless net.empty?
            @logger.error '!!! Unknown references !!!'
            net.each do |name|
              @logger.error "  #{name} from #{refs[name][0]}:#{refs[name][1]}"
            end
            abort!
          end
          net = (prms-refs.keys)
          unless net.empty?
            @logger.warn '!!! Unused Parameters !!!'
            net.each do |name|
              @logger.warn "  #{name}"
            end
          end
          net = (rscs-refs.keys)
          unless net.empty?
            @logger.info '!!! Unreported Resources !!!'
            net.each do |name|
              @logger.info "  #{name}"
            end
          end
          @logger.info '  References validated'
        end

        def save_template(output_file,compiled)
          filn = output_file
          file = output_file
          file = File.expand_path(output_file) if @config[:expandedpaths]
          if File.exists?(file)
            file = File.realpath(file)
          end
          logStep "Writing compiled file to #{filn}..."
          begin
            hash = {}
            compiled.each do |item,value|
              unless value.nil?
                if (not value.is_a?(Hash)) or (value.count > 0)
                  hash[item] = value
                end
              end
            end

            dir  = File.dirname(output_file)
            file = File.basename(output_file)
            sect = dir == '.' ? Dir.pwd : dir
            sect = File.basename(sect) unless @config[:expandedpaths]
            save_section(dir, file, @config[:format], sect, hash, '', 'template')

            parameters = []
            if (@config[:parametersfile] or @config[:stackinifile]) and hash.has_key?('Parameters')
              hash['Parameters'].each do |par,hsh|
                # noinspection RubyStringKeysInHashInspection
                parameters <<   {
                    'ParameterKey' => par,
                    'ParameterValue' => hsh.has_key?('Default') ? hsh['Default'] : '',
                    # 'UsePreviousValue' => false,
                }
              end
            end

            if @config[:parametersfile] and parameters.size > 0
              dir  = File.dirname(@config[:parametersfile])
              file = File.basename(@config[:parametersfile])
              sect = dir == '.' ? Dir.pwd : dir
              sect = File.basename(sect) unless @config[:expandedpaths]

              save_section(dir, file, @config[:format], sect, parameters, '', 'parameters')
            end

            if @config[:stackinifile] and parameters.size > 0
              dir  = File.dirname(@config[:stackinifile])
              file = File.basename(@config[:stackinifile])
              sect = dir == '.' ? Dir.pwd : dir
              sect = File.basename(sect) unless @config[:expandedpaths]

              save_inifile(dir, file, sect, parameters, 'parameters')
            end
            @logger.info '  Compiled file written.'
          rescue
            abort! "!!! Could not write compiled file: #{$!}"
          end
        end

        def load_spec(spec=nil)
          if spec
            abs = nil
            [spec, File.join(@config[:brick_path_list],spec)].flatten.each do |p|
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
              abort! 'Unable to open specification'+ (abs.nil? ? " or {.,#{@config[:brick_path_list].join(',')}/}#{spec} not found" : ": #{abs}")
            end
          else
            abort! 'No specification provided'
          end
        end

        protected

        require 'aws/cfn/compiler/mixins/options'
        include Aws::Cfn::Compiler::Options

        require 'aws/cfn/compiler/mixins/load'
        include Aws::Cfn::Compiler::Load

        require 'aws/cfn/compiler/mixins/parse'
        include Aws::Cfn::Compiler::Parse

        require 'aws/cfn/compiler/mixins/compile'
        include Aws::Cfn::Compiler::Compile

        require 'aws/cfn/compiler/mixins/save'
        include Aws::Cfn::Compiler::Save

      end
    end
  end
end
