# frozen_string_literal: true

module TravelPay
  class ClaimsController < ApplicationController
    before_action :authorize

    def index
      veis_token = client.request_veis_token

      sts_token = client.request_sts_token(@current_user)
      btsss_token = client.request_btsss_token(veis_token, sts_token)

      begin
        claims = client.get_claims(veis_token, btsss_token)
      rescue Faraday::Error => e
        raise common_exception(e)
      end

      render json: claims, each_serializer: TravelPay::ClaimSerializer, status: :ok
    end

    private

    def client
      @client ||= TravelPay::Client.new
    end

    def common_exception(e)
      case e
      when Faraday::ResourceNotFound
        Common::Exceptions::ResourceNotFound.new
      else
        Common::Exceptions::InternalServerError.new
      end
    end
  end
end
