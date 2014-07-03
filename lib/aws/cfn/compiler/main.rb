

module Aws
  module Cfn
    module Compiler
      class Main < Base

        def run

          parse_options

          set_config_options

          load_spec @config[:specification]

          parse

          compiled = compile_spec

          validate(compiled)

          output_file = @config[:template] || 'compiled.json'
          save_template(output_file,compiled)

          @logger.step '*** Compiled Successfully ***'
        end

      end
    end
  end
end
