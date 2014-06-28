require "aws/cfn/compiler/version"
require "aws/cfn/compiler/base"
require "aws/cfn/compiler/main"

module Aws::Cfn::Compiler
  attr_accessor :binding

  @binding ||= {}

  def self.binding=(b)
    @binding = b
  end

  def self.binding
    @binding
  end
end