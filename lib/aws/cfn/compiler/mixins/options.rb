module Aws
  module Cfn
    module Compiler
      module Options

        # TODO: [2014-06-29 Christo] Hook into super class and add on options instead of starting from scratch every time
        def parse_options

          setup_options

          @opts.on :b, :brick_path=,    'A list of paths to template components (bricks). May also set as the BRICK_PATH environment variable.', { as: String, default: 'bricks' }
          @opts.on :S, :stack_path=,    'A list of paths to stacks. May also set as the STACK_PATH environment variable.', { as: String, default: '.' }
          @opts.on :F, :format=,        'The output format of the components. [JSON|YAML|Ruby]', { as: String, match: @format_regex, default: 'yaml' }
          @opts.on :s, :specification=, 'The specification to use when selecting components. A JSON or YAML file', { as: String }
          @opts.on :f, :formatversion=, 'The AWS Template format version. ', {as: String,
                                                                              default: '2010-09-09' }
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

          unless @opts[:specification]
            puts @opts
            abort! "Missing required option --specification"
          end

        end

        def set_config_options

          @config[:precedence]    = @opts[:precedence].split(%r',+\s*').reverse

          @optional             ||= {}
          @optional[:directory]   = true
          setup_config

          set_config_path_option(@config[:stack_path],'STACK_PATH','.',:stack_path_list,'stack path')
          set_config_path_option(@config[:brick_path],'BRICK_PATH',@config[:directory],:brick_path_list,'brick path',:stack_path_list)

        end

        def set_config_path_option(value,envstr,default,listsym,type,relto=nil)
          if value
            path = value
          elsif ENV[envstr]
            path = ENV[envstr]
          else
            path = default
          end
          if path
            @config[listsym] = parseList(path, ':')
            newlist = @config[listsym].map{ |r|
              if relto
                if r.match(%r'^/')
                  # Absolute paths not relative to stacks
                  r
                else
                  a = []
                  @config[relto].each{|b|
                    # noinspection RubyAssignmentExpressionInConditionalInspection
                    if File.directory?(p=File.expand_path(File.join(b,r)))
                      a << File.realpath(p)
                    end
                  }
                  a
                end
              else
                File.expand_path(r)
              end
            }
            @config[listsym] = newlist.flatten.uniq

            mia = find_mia(@config[listsym])

            if mia.size > 0
              report_mia(path, mia, type)
            end

            @config[listsym].each { |p|
              if File.directory?((lib = File.join(p, 'lib')))
                $:.unshift lib
              end
            }
          end
        end

        def report_mia(path, mia, type)
          hints = []
          mia.each do |p|
            hints << hint_paths(p, Dir.pwd)
          end
          hints.flatten!
          abort! "Invalid #{type}: #{path}!
              #{mia.size > 1 ? 'These' : 'This'} path#{mia.size > 1 ? 's' : ''} does not exist or cannot be read!\n #{mia.join("\n\t")}
              Did you mean one of these? #{@config[:expandedpaths] ? "(Above #{Dir.pwd})" : ""}
                 \t#{hints.join("\n\t")}\n"
        end

        def find_mia(list)
          mia = []
          list.each do |path|
            unless File.directory? path
              mia << path
            end
          end
          mia
        end

        def hint_paths(p,pwd,n=0,rel='',f=nil)
          hints = []
          d = p
          until File.directory?(d)
            if d == '.'
              return hints
            end
            d = File.dirname(d)
          end
          unless f
            q = d
            Range.new(1,n).each do
              d = File.dirname(d)
            end
            f = File.basename(p)
            r = pwd.gsub(%r'^#{q}','').split(File::SEPARATOR)
            if r.size > 0
              r = r[1..-1]
            end
            if r.size > 0
              rel = r.map{|_| '..'}.join(File::SEPARATOR)
            end
            pwd = d
          end
          Dir.glob("#{d}/*").each do |path|
            if File.directory?(path)
              if path.match %r'/#{f}'
                hints << File.join(rel,path.gsub(%r'^#{File.dirname(d)}',''))
              else
                hints << hint_paths(path,pwd,n,rel,f)
              end
            end
          end
          hints.flatten
        end

      end
    end
  end
end
