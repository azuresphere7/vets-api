# frozen_string_literal: true

require 'rails_helper'
require 'support/sm_client_helpers'
require 'support/shared_examples_for_mhv'

RSpec.describe 'Messaging Preferences Integration', type: :request do
  include SM::ClientHelpers
  include SchemaMatchers

  let(:mhv_account_type) { 'Premium' }
  let(:va_patient) { true }
  let(:current_user) { build(:user, :mhv, va_patient:, mhv_account_type:) }

  before do
    sign_in_as(current_user)
  end

  context 'when sm session policy is enabled' do
    before do
      Flipper.enable(:mhv_sm_session_policy)
      Timecop.freeze(Time.zone.parse('2017-05-01T19:25:00Z'))
      sign_in_as(current_user)
    end

    after do
      Flipper.disable(:mhv_sm_session_policy)
      Timecop.return
    end

    context 'when NOT authorized' do
      before do
        VCR.insert_cassette('sm_client/session_error')
        get '/my_health/v1/messaging/preferences'
      end

      after do
        VCR.eject_cassette
      end

      include_examples 'for user account level', message: 'You do not have access to messaging'
    end

    context 'when authorized' do
      before do
        VCR.insert_cassette('sm_client/session')
      end

      after do
        VCR.eject_cassette
      end

      it 'responds to GET #show of preferences' do
        VCR.use_cassette('sm_client/preferences/fetches_email_settings_for_notifications') do
          get '/my_health/v1/messaging/preferences'
        end

        expect(response).to be_successful
        expect(response.body).to be_a(String)
        attrs = JSON.parse(response.body)['data']['attributes']
        expect(attrs['email_address']).to eq('muazzam.khan@va.gov')
        expect(attrs['frequency']).to eq('daily')
      end

      it 'responds to PUT #update of preferences' do
        VCR.use_cassette('sm_client/preferences/sets_the_email_notification_settings', record: :none) do
          params = { email_address: 'kamyar.karshenas@va.gov',
                     frequency: 'none' }
          put '/my_health/v1/messaging/preferences', params:
        end

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['data']['id'])
          .to eq('17126b0821ad0472ae11944e9861f82d6bdd17801433e200e6a760148a4866c3')
        expect(JSON.parse(response.body)['data']['attributes'])
          .to eq('email_address' => 'kamyar.karshenas@va.gov', 'frequency' => 'none')
      end

      it 'requires all parameters for update' do
        VCR.use_cassette('sm_client/preferences/sets_the_email_notification_settings', record: :none) do
          params = { email_address: 'kamyar.karshenas@va.gov' }
          put '/my_health/v1/messaging/preferences', params:
        end

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'rejects unknown frequency parameters' do
        VCR.use_cassette('sm_client/preferences/sets_the_email_notification_settings', record: :none) do
          params = { email_address: 'kamyar.karshenas@va.gov',
                     frequency: 'hourly' }
          put '/my_health/v1/messaging/preferences', params:
        end

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns a custom exception mapped from i18n when email contains spaces' do
        VCR.use_cassette('sm_client/preferences/raises_a_backend_service_exception_when_email_includes_spaces') do
          params = { email_address: 'kamyar karshenas@va.gov',
                     frequency: 'daily' }
          put '/my_health/v1/messaging/preferences', params:
        end

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)['errors'].first['code']).to eq('SM152')
      end
    end
  end

  context 'when legacy sm policy' do
    before do
      Flipper.disable(:mhv_sm_session_policy)
      allow(SM::Client).to receive(:new).and_return(authenticated_client)
    end

    context 'Basic User' do
      let(:mhv_account_type) { 'Basic' }

      before { get '/my_health/v1/messaging/preferences' }

      include_examples 'for user account level', message: 'You do not have access to messaging'
      include_examples 'for non va patient user', authorized: false, message: 'You do not have access to messaging'
    end

    context 'Premium User' do
      let(:mhv_account_type) { 'Premium' }

      context 'not a va patient' do
        before { get '/my_health/v1/messaging/preferences' }

        let(:va_patient) { false }
        let(:current_user) do
          build(:user, :mhv, :no_vha_facilities, va_patient:, mhv_account_type:)
        end

        include_examples 'for non va patient user', authorized: false, message: 'You do not have access to messaging'
      end

      describe 'preferences' do
        it 'responds to GET #show of preferences' do
          VCR.use_cassette('sm_client/preferences/fetches_email_settings_for_notifications') do
            get '/my_health/v1/messaging/preferences'
          end

          expect(response).to be_successful
          expect(response.body).to be_a(String)
          attrs = JSON.parse(response.body)['data']['attributes']
          expect(attrs['email_address']).to eq('muazzam.khan@va.gov')
          expect(attrs['frequency']).to eq('daily')
        end
      end
    end
  end
end
