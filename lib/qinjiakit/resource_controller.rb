# frozen_string_literal: true

module Qinjiakit
  module ResourceController
    extend ActiveSupport::Concern
    include Qinjiakit::Controller

    included do
      before_action :set_resource, only: [:show, :update, :destroy]
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
  end
end