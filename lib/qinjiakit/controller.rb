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
      before_action :set_resource, only: [:show, :update, :destroy]

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

    # GET /resources
    def index
      @resources = filtered_resources
      authorize @resources
      @pagy, @resources = pagy(apply_scopes(@resources))
      render_success!(@resources, pagination: pagination_metadata)
    end

    # GET /resources/:id
    def show
      authorize @resource
      render_success!(@resource)
    end

    # POST /resources
    def create
      @resource = resource_class.new(resource_params)
      authorize @resource
      if @resource.save
        render_success!(@resource)
      else
        render_error!(@resource.errors.full_messages.join(', '))
      end
    end

    # PATCH/PUT /resources/:id
    def update
      authorize @resource
      if @resource.update(resource_params)
        render_success!(@resource)
      else
        render_error!(@resource.errors.full_messages.join(', '))
      end
    end

    # DELETE /resources/:id
    def destroy
      authorize @resource
      @resource.destroy
      render_success!(nil, msg: 'Resource successfully deleted')
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

    def set_resource
      @resource = apply_scopes(accessible_resources).find(params[:id])
    end

    def resource_class
      @resource_class ||= controller_name.classify.constantize
    end

    def resource_params
      params.require(controller_name.singularize).permit(permitted_params)
    end

    def permitted_params
      []
    end

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

    def accessible_resources
      policy_scope(resource_class)
    end

    def filtered_resources
      resources = accessible_resources
      filter_params.each do |key, value|
        resources = apply_filter(resources, key, value)
      end
      resources
    end

    def apply_filter(resources, key, value)
      filter = filter_mappings[key.to_sym]
      return resources unless filter

      case filter[:type]
      when :exact
        resources.where(key => value)
      when :range
        min, max = value.split(',')
        resources.where(key => min..max)
      when :like
        resources.where("#{key} LIKE ?", "%#{value}%")
      when :custom
        resources.public_send(filter[:method], value)
      else
        resources
      end
    end

    def filter_params
      params.fetch(:filters, {}).permit(allowed_filters)
    end

    def allowed_filters
      []
    end

    def filter_mappings
      {}
    end

    def apply_scopes(relation)
      relation = relation.includes(*eager_load_associations) if eager_load_associations.any?
      relation
    end

    def eager_load_associations
      []
    end

    def serialize_data(data)
      if data.respond_to?(:map)
        data.map { |item| serialize_resource(item) }
      else
        serialize_resource(data)
      end
    end

    def serialize_resource(resource)
      serialized = resource.as_json(include: included_associations)
      append_custom_attributes(serialized, resource)
      serialized
    end

    def included_associations
      []
    end

    def append_custom_attributes(serialized, resource)
      custom_attributes.each do |attr|
        serialized[attr] = resource.public_send(attr) if resource.respond_to?(attr)
      end
    end

    def custom_attributes
      []
    end

    def pagination_metadata
      {
        current_page: @pagy.page,
        per_page: @pagy.items,
        total_pages: @pagy.pages,
        total_count: @pagy.count
      }
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
