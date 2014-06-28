
require 'json'
require 'ap'
require 'yaml'
require 'slop'

module Aws
  module Cfn
    module Compiler
      class Main < Base

        def run

          @opts = Slop.parse(help: true) do
            # command File.basename(__FILE__,'.rb')
            on :d, :directory=,     'The directory containing template sections', as: String
            on :o, :output=,        'The JSON file to output', as: String
            on :s, :specification=, 'The specification to use when selecting components. A JSON or YAML file or JSON object', as: String
            on :f, :formatversion=, 'The AWS Template format version. ', {  as: String,
                                                                            optional_argument: true,
                                                                            default: '2010-09-09' }
            on :p, :precedence=,    'The precedence of template component types. Default: rb,ruby,yaml,yml,json,js', { as: String,
                                                                                                                  default: 'rb,ruby,yaml,yml,json,js' }
            on :t, :description=,   "The AWS Template description. Default: output basename or #{File.basename(__FILE__,'.rb')}", { as: String,
                                                                                                                                    default: File.basename(__FILE__,'.rb') }
            on :x, :expandedpaths,  'Show expanded paths in output', { as: String,
                                                                       optional_argument: true,
                                                                       default: 'off',
                                                                       match: %r/0|1|yes|no|on|off|enable|disable|set|unset|true|false|raw/i }
            on :O, :overwrite,      'Overwrite existing generated source files. (HINT: Think twice ...)', { as: String,
                                                                                                            optional_argument: true,
                                                                                                            default: 'off',
                                                                                                            match: %r/0|1|yes|no|on|off|enable|disable|set|unset|true|false|raw/i }
          end

          unless @opts[:directory]
            puts @opts
            exit
          end

          @config[:precedence]    = @opts[:precedence].split(%r',+\s*').reverse
          @config[:expandedpaths] = @opts[:expandedpaths].downcase.match %r'^(1|true|on|yes|enable|set)$'
          @config[:directory]     = @opts[:directory]

          load_spec @opts[:specification]

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

          validate(compiled)

          output_file = @opts[:output] || 'compiled.json'
          save_template(output_file,compiled)

          @logger.step '*** Compiled Successfully ***'
        end

      end
    end
  end
end
