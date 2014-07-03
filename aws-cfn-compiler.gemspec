# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'aws/cfn/compiler/version'

Gem::Specification.new do |spec|
  spec.name          = "aws-cfn-compiler"
  spec.version       = Aws::Cfn::Compiler::VERSION
  spec.authors       = ["PKinney"]
  spec.email         = ["pkinney@github.com"]
  spec.summary       = %q{A simple script to compile and perform some validation for CloudFormation scripts.}
  spec.description   = %q{The idea is to create a folder structure to better manage pieces of a CloudFormation deployment. Additionally, writing in JSON is hard, so the compiler takes YAML files as well.}
  spec.homepage      = "https://github.com/dldinternet/aws-cfn-compiler"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency 'awesome_print', '~> 1.2', '>= 1.2.0'
  spec.add_dependency 'psych'
  spec.add_dependency 'json'
  spec.add_dependency 'slop'
  spec.add_dependency 'inifile'
  spec.add_dependency 'aws-cfn-dsl', '>= 0.9.2'
  spec.add_dependency 'dldinternet-mixlib-cli', '>= 0.2.0'
  spec.add_dependency 'dldinternet-mixlib-logging', '>= 0.4.0'

end
