module Riiif
  class ImagesController < ::ApplicationController
    before_action :link_header, only: [:show, :info]

    rescue_from Riiif::InvalidAttributeError do
      head 400
    end

    def show
      begin
        image = model.new(image_id)
        status = if authorization_service.can?(:show, image)
                   :ok
                 else
                   :unauthorized
                 end
      rescue ImageNotFoundError
        status = :not_found
      end

      image = not_found_image unless status == :ok

      data = image.render(image_request_params)
      headers['Access-Control-Allow-Origin'] = '*'
      # Set a Cache-Control header
      expires_in cache_expires, public: public_cache? if status == :ok
      send_data data,
                status: status,
                type: Mime::Type.lookup_by_extension(params[:format]),
                disposition: 'inline'
    end

    def info
      image = model.new(image_id)
      if authorization_service.can?(:info, image)
        headers['Access-Control-Allow-Origin'] = '*'
        # Set a Cache-Control header
        expires_in cache_expires, public: public_cache?
        render json: image.info.to_h.merge(server_info), content_type: 'application/ld+json'
      else
        render json: { error: 'unauthorized' }, status: :unauthorized
      end
    end

    # this is a workaround for https://github.com/rails/rails/issues/25087
    def redirect
      # This was attempted with just info_path, but it gave a NoMethodError
      redirect_to riiif.info_path(params[:id])
    end

    protected

      LEVEL1 = 'http://iiif.io/api/image/2/level1.json'.freeze

      # @return seconds before the request expires. Defaults to 1 year.
      def cache_expires
        1.year
      end

      # Should the Cache-Control header be public? Override this if you want to have a
      # public Cache-Control set.
      # @return FalseClass
      def public_cache?
        false
      end

      def model
        params.fetch(:model, 'riiif/image').camelize.constantize
      end

      def image_id
        params[:id]
      end

      ##
      # @return [ActiveSupport::HashWithIndifferentAccess]
      def image_request_params
        result = params.permit(:region, :size, :rotation, :quality, :format).to_h
        return result.with_indifferent_access if Rails.version < '5'
        result
      end

      def authorization_service
        model.authorization_service.new(self)
      end

      def link_header
        response.headers['Link'] = "<#{LEVEL1}>;rel=\"profile\""
      end

      def not_found_image
        raise "Not found image doesn't exist" unless Riiif.not_found_image
        model.new(image_id, Riiif::File.new(Riiif.not_found_image))
      end

      CONTEXT = '@context'.freeze
      CONTEXT_URI = 'http://iiif.io/api/image/2/context.json'.freeze
      ID = '@id'.freeze
      PROTOCOL = 'protocol'.freeze
      PROTOCOL_URI = 'http://iiif.io/api/image'.freeze
      PROFILE = 'profile'.freeze

      def server_info
        {
          CONTEXT => CONTEXT_URI,
          ID => request.original_url.sub('/info.json', ''),
          PROTOCOL => PROTOCOL_URI,
          PROFILE => [LEVEL1, 'formats' => model::OUTPUT_FORMATS]
        }
      end
  end
end
