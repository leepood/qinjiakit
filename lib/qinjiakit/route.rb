# frozen_string_literal: true

module Qinjiakit
  module Route
    def draw_routes(ns)
      namespace ns do
        api_controllers(ns).each do |controller|
          resources controller.underscore.to_sym
        end
      end
    end

    private

    def api_controllers(ns)
      Dir[Rails.root.join('app', 'controllers', ns.to_s, '**', '*_controller.rb')]
        .map { |path| File.basename(path, '.rb').classify }
        .select { |controller| controller_compatible?(ns, controller) }
        .map { |controller| controller.sub('Controller', '') }
    end

    def controller_compatible?(ns, controller)
      klass = "#{ns.to_s.classify}::#{controller}".constantize
      klass.included_modules.include?(Controller)
    rescue NameError
      false
    end
  end

end
