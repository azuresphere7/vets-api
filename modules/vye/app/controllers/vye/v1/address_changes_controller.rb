# frozen_string_literal: true

module Vye
  module Vye::V1
    class Vye::V1::AddressChangesController < Vye::V1::ApplicationController
      include Pundit::Authorization
      service_tag 'vye'

      def create
        authorize user_info, policy_class: Vye::UserInfoPolicy

        user_info.address_changes.create!(create_params)
      end

      private

      def create_params
        params.permit(%i[
                        rpo benefit_type veteran_name address1 address2 address3 address4 city state zip_code
                      ])
      end
    end
  end
end