require 'inifile'
module Aws
  module Cfn
    module Compiler
      module Save

        def save_inifile(dir, file, section, parameters, brick=nil)
          brick ||= "INI #{section}"
          path = File.join(File.expand_path(dir), file)
          filn = if @config[:expandedpaths]
                   path
                 else
                   File.join(dir, file)
                 end
          logStep "Saving #{brick} to #{filn} "

          if i_am_maintainer(path) or @config[:force]
            begin
              ini = IniFile.new

              # noinspection RubyStringKeysInHashInspection
              parms = {
                  'region' => 'us-east-1'
              }
              parameters.map{ |p| parms[p['ParameterKey']] = p['ParameterValue'] }
              ini['<StackName>'] = parms
              ini.write( filename: path )
              @logger.info "  saved #{filn}."
            rescue
              abort! "!!! Could not write file #{path}: #{$!}"
            end
          else
            @logger.warn "  Did not overwrite #{filn}."
          end
        end

        def save_section(dir, file, format, section, hash, join='/', brick=nil)
          brick ||= "brick #{hash.keys[0]}"
          path = File.join(File.expand_path(dir), file)
          filn = if @config[:expandedpaths]
                   path
                 else
                   File.join(dir, file)
                 end
          logStep "Saving #{brick} to #{filn} "
          # noinspection RubyAssignmentExpressionInConditionalInspection
          if match = file.match(%r'\.(.*)$')
            if (section != '') and (not formats_compatible?(format, match[1]))
              msg = "The file extension (#{match[1]}) does not match the chosen output format (#{format})!"
              if @config[:force]
                logger.warn msg
              else
                abort! "#{msg}\n\tIf you are SURE this is what you want then use the --force option!"
              end
            end
          end

          if i_am_maintainer(path) or @config[:force]
            begin
              File.open path, File::CREAT|File::TRUNC|File::RDWR, 0644 do |f|
                case format
                  when /ruby|rb|yaml|yml/
                    f.write maintainer_comment('')
                    f.write hash.to_yaml line_width: 1024, indentation: 4, canonical: false
                  when /json|js/
                    # You wish ... f.write maintainer_comment('')
                    f.write JSON.pretty_generate(hash, { indent: "\t", space: ' '})
                  else
                    abort! "Internal: Unsupported format #{format}. Should have noticed this earlier!"
                end
                f.close
              end
              @logger.info "  saved #{filn}."
            rescue
              abort! "!!! Could not write file #{path}: #{$!}"
            end
          else
            @logger.warn "  Did not overwrite #{filn}."
          end
        end

      end
    end
  end
end
