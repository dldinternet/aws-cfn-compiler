module Aws
  module Cfn
    module Compiler
      module Options

        # TODO: [2014-06-29 Christo] Hook into super class and add on options instead of starting from scratch every time
        def parse_options

          setup_options

          @opts.on :F, :format=,        'The output format of the components. [JSON|YAML|Ruby]', { as: String, match: @format_regex, default: 'yaml' }
          @opts.on :s, :specification=, 'The specification to use when selecting components. A JSON or YAML file', { as: String
          }
          @opts.on :f, :formatversion=, 'The AWS Template format version. ', {as: String,
                                                                              default: '2010-09-09'
          }
          @opts.on :D, :description=,    'The AWS Template description. Default: template name', { as: String }
          @opts.on :p, :parametersfile=, 'The parameters file for the template', { as: String }
          @opts.on :i, :stackinifile=,   'The INI file for the stack builder == build.py', { as: String }
          @opts.on :P, :precedence=,     'The precedence of template component types. Default: rb,ruby,yaml,yml,json,js', { as: String,
                                                                                                                        default: 'rb,ruby,yaml,yml,json,js', }

          @opts.parse!

          if ARGV.size > 0
            puts @opts
            puts "Extra arguments! #{ARGV}"
            exit 1
          end
        end

        def set_config_options

          @config[:precedence]    = @opts[:precedence].split(%r',+\s*').reverse

          setup_config

        end

      end
    end
  end
end
