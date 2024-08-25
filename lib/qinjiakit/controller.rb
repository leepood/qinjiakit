# frozen_string_literal: true

require 'active_support/concern'
require 'pundit'
require 'pagy'
require 'dry-schema'

module Qinjiakit
  module Controller
    extend ActiveSupport::Concern

    included do
      include Pundit::Authorization
      include Pagy::Backend

      class_attribute :param_rules

      self.param_rules = {}

      before_action :authenticate_user!
      before_action :validate_params

      after_action :verify_authorized
      after_action :verify_policy_scoped
      after_action :set_cache_headers

      around_action :handle_exceptions

      if respond_to?(:helper_method)
        helper_method :current_user
      end
    end

    class_methods do
      def params_for(action, &block)
        self.param_rules[action] = block
      end

      def skip_auth_for(*actions)
        skip_before_action :authenticate_user!, only: actions
        skip_after_action :verify_authorized, only: actions
      end
    end

    class ResponseError < StandardError
      attr_accessor :data

      def initialize(data = {})
        @data = data
        super
      end
    end

    protected

    def render_success!(data, code: 200, msg: 'Success', pagination: nil)
      ret = { code: code, msg: msg, data: data }
      ret[:pagination] = pagination if pagination.present?
      raise ResponseError.new(ret)
    end

    def render_error!(msg, code: -1, data: nil)
      raise ResponseError.new({ code: code, msg: msg, data: data })
    end

    def authenticate_user!
      method_name = Qinjiakit.configuration.authenticate_user_method
      @current_user = send(method_name) if method_name.present?
      user_not_authorized unless @current_user
    end

    def current_user
      @current_user
    end

    private

    def validate_params
      return unless self.class.param_rules[action_name.to_sym]

      schema = Dry::Schema.Params(&self.class.param_rules[action_name.to_sym])
      result = schema.call(params.to_unsafe_h)

      if result.failure?
        render_error!(result.errors.to_h, code: 400)
      end
    end

    def set_cache_headers
      return unless request.get?

      if @resource.respond_to?(:cache_key)
        fresh_when(@resource)
      elsif @resources.respond_to?(:maximum)
        fresh_when(@resources)
      end
    end

    def render_response(exception)
      render json: exception.data, status: :ok
    end

    def user_not_authorized
      render json: { code: 403, msg: '无权访问' }, status: :ok
    end

    def record_not_found
      render json: { code: 403, msg: '访问的资源不存在' }, status: :ok
    end

    def handle_error(e)
      Rails.logger.error "Unhandled error: #{e.class} #{e.message}\n#{e.backtrace.join("\n")}"
      render json: { code: 500, msg: "#{e.class}\n#{e.backtrace.join('\n')}" }, status: :ok
    end

    def handle_exceptions
      yield
    rescue ResponseError => e
      render_response(e)
    rescue Pundit::NotAuthorizedError
      user_not_authorized
    rescue ActiveRecord::RecordNotFound
      record_not_found
    rescue StandardError => e
      handle_error(e)
    end
  end
end