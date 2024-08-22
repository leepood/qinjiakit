# frozen_string_literal: true

module Qinjiakit
  class Configuration
    attr_accessor :authenticate_user_method

    def initialize
      @authenticate_user_method = nil
    end

  end
end