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

  spec.add_dependency "awesome_print"
  spec.add_dependency "psych"
  spec.add_dependency "json"
  spec.add_dependency 'aws-cfn-dsl', '>= 0.0.1', '~> 0.0'
  spec.add_dependency "slop"

  spec.add_development_dependency 'bundler', "~> 1.6"
  spec.add_development_dependency 'rake'
end
