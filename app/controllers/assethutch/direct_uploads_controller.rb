# frozen_string_literal: true

module Assethutch
  # Proxies the two control-plane calls of a browser-direct upload. The bytes
  # still go from the browser straight to storage.
  class DirectUploadsController < Assethutch.config.direct_upload_parent_controller.constantize
    before_action :authorize_assethutch_upload!

    def create
      upload = Assethutch.client.create_upload(
        policy: params.require(:policy), filename: params.require(:filename),
        content_type: params.require(:content_type), byte_size: params.require(:byte_size)
      )
      render json: { upload: upload.to_h, file: upload.file.to_h }, status: :created
    rescue Assethutch::Error => e
      render_assethutch_error(e)
    end

    def complete
      file = Assethutch.client.complete_upload(params[:id])
      render json: { file: file.to_h }
    rescue Assethutch::Error => e
      render_assethutch_error(e)
    end

    private

    def authorize_assethutch_upload!
      authorizer = Assethutch.config.authorize_direct_upload
      if authorizer
        args = [ self, params[:policy].to_s ].first(authorizer.arity.negative? ? 2 : authorizer.arity)
        return if instance_exec(*args, &authorizer)
      end

      message = authorizer ? "Not allowed to upload here" : "Direct uploads are disabled: set Assethutch.config.authorize_direct_upload"
      render json: { error: { code: "forbidden", message: message } }, status: :forbidden
    end

    def render_assethutch_error(error)
      status = error.respond_to?(:status) && error.status.to_i.between?(400, 599) ? error.status : :unprocessable_entity
      render json: { error: { code: error.respond_to?(:code) ? error.code : "error", message: error.message } }, status: status
    end
  end
end
