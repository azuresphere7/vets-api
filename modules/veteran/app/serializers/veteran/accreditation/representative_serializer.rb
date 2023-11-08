# frozen_string_literal: true

module Veteran
  module Accreditation
    class RepresentativeSerializer < ActiveModel::Serializer
      attribute :full_name
      # rubocop:disable Naming/VariableNumber
      attribute :address_line_1
      attribute :address_line_2
      attribute :address_line_3
      # rubocop:enable Naming/VariableNumber
      attribute :address_type
      attribute :city
      attribute :country_name
      attribute :country_code_iso3
      attribute :province
      attribute :international_postal_code
      attribute :state_code
      attribute :zip_code
      attribute :zip_suffix
      attribute :poa_codes, array: true
      attribute :phone
      attribute :email
      attribute :lat
      attribute :long
      attribute :distance

      def distance
        object.distance / Veteran::Service::Constants::METERS_PER_MILE
      end
    end
  end
end