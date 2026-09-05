# frozen_string_literal: true

module FileHutch
  # Proxies the two control-plane calls of a browser-direct upload. The bytes
  # still go from the browser straight to storage.
  class DirectUploadsController < FileHutch.config.direct_upload_parent_controller.constantize
    before_action :authorize_file_hutch_upload!

    def create
      upload = FileHutch.client.create_upload(
        policy: params.require(:policy), filename: params.require(:filename),
        content_type: params.require(:content_type), byte_size: params.require(:byte_size)
      )
      render json: { upload: upload.to_h, file: upload.file.to_h }, status: :created
    rescue FileHutch::Error => e
      render_file_hutch_error(e)
    end

    def complete
      file = FileHutch.client.complete_upload(params[:id])
      render json: { file: file.to_h }
    rescue FileHutch::Error => e
      render_file_hutch_error(e)
    end

    private

    def authorize_file_hutch_upload!
      authorizer = FileHutch.config.authorize_direct_upload
      if authorizer
        arity = authorizer.arity.negative? ? 2 : authorizer.arity
        args = [ self, arity >= 2 ? file_hutch_requested_policy : nil ].first(arity)
        return if instance_exec(*args, &authorizer)
      end

      message = authorizer ? "Not allowed to upload here" : "Direct uploads are disabled: set FileHutch.config.authorize_direct_upload"
      render json: { error: { code: "forbidden", message: message } }, status: :forbidden
    end

    # On create the policy is in the request. On complete it is not, but it is a
    # property of the file being finalized, so it is looked up — and looked up
    # rather than trusted from the client, which could name any policy it liked.
    # Only authorizers that actually take a policy pay for the lookup.
    def file_hutch_requested_policy
      return params[:policy].to_s if action_name == "create"

      FileHutch.client.file(params[:id]).policy.to_s
    rescue StandardError
      # A lookup that fails must not become a 500. An empty policy matches
      # nothing, so an authorizer that checks the policy denies; one that
      # ignores it is unaffected either way.
      ""
    end

    def render_file_hutch_error(error)
      status = error.respond_to?(:status) && error.status.to_i.between?(400, 599) ? error.status : :unprocessable_entity
      render json: { error: { code: error.respond_to?(:code) ? error.code : "error", message: error.message } }, status: status
    end
  end
end
