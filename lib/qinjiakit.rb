# frozen_string_literal: true

require_relative "qinjiakit/version"
require_relative 'qinjiakit/route'
require_relative 'qinjiakit/configuration'

module Qinjiakit

  class << self
    attr_accessor :configuration
  end

  def self.configure
    self.configuration ||= Configuration.new
    yield(configuration)
  end

end
