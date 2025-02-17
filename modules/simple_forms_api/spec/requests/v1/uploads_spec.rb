# frozen_string_literal: true

require 'rails_helper'
require 'simple_forms_api_submission/metadata_validator'
require 'common/file_helpers'

RSpec.describe 'Forms uploader', type: :request do
  forms = [
    # TODO: Restore this test when we release 26-4555 to production.
    # 'vba_26_4555.json',
    'vba_21_4142.json',
    'vba_21_10210.json',
    'vba_21p_0847.json',
    'vba_21_0972.json',
    'vba_21_0845.json',
    'vba_40_0247.json',
    'vba_21_0966.json',
    'vba_20_10206.json',
    'vba_40_10007.json',
    'vba_20_10207-veteran.json',
    'vba_20_10207-non-veteran.json'
  ]

  authenticated_forms = forms - %w[vba_40_0247.json vba_21_10210.json vba_21p_0847.json
                                   vba_40_10007.json]

  describe '#submit' do
    context 'going to Lighthouse Benefits Intake API' do
      let(:metadata_file) { "#{file_seed}.SimpleFormsApi.metadata.json" }
      let(:file_seed) { 'tmp/some-unique-simple-forms-file-seed' }

      before do
        VCR.insert_cassette('lighthouse/benefits_intake/200_lighthouse_intake_upload_location')
        VCR.insert_cassette('lighthouse/benefits_intake/200_lighthouse_intake_upload')
        allow(Common::FileHelpers).to receive(:random_file_path).and_return(file_seed)
      end

      after do
        VCR.eject_cassette('lighthouse/benefits_intake/200_lighthouse_intake_upload_location')
        VCR.eject_cassette('lighthouse/benefits_intake/200_lighthouse_intake_upload')
        Common::FileHelpers.delete_file_if_exists(metadata_file)
      end

      forms.each do |form|
        fixture_path = Rails.root.join('modules', 'simple_forms_api', 'spec', 'fixtures', 'form_json', form)
        data = JSON.parse(fixture_path.read)

        it 'makes the request' do
          allow(SimpleFormsApiSubmission::MetadataValidator).to receive(:validate)

          post '/simple_forms_api/v1/simple_forms', params: data

          expect(SimpleFormsApiSubmission::MetadataValidator).to have_received(:validate)
          expect(response).to have_http_status(:ok)
        end

        it 'saves a FormSubmissionAttempt' do
          allow(SimpleFormsApiSubmission::MetadataValidator).to receive(:validate)

          expect do
            post '/simple_forms_api/v1/simple_forms', params: data
          end.to change(FormSubmissionAttempt, :count).by(1)
        end
      end

      authenticated_forms.each do |form|
        fixture_path = Rails.root.join('modules', 'simple_forms_api', 'spec', 'fixtures', 'form_json', form)
        data = JSON.parse(fixture_path.read)

        context 'authenticated user' do
          before do
            user = create(:user)
            sign_in_as(user)
            create(:in_progress_form, user_uuid: user.uuid, form_id: data['form_number'])
          end

          it 'clears the InProgressForm' do
            allow(SimpleFormsApiSubmission::MetadataValidator).to receive(:validate)

            expect do
              post '/simple_forms_api/v1/simple_forms', params: data
            end.to change(InProgressForm, :count).by(-1)
          end
        end
      end

      context 'request with intent to file' do
        context 'authenticated' do
          before do
            sign_in
            allow_any_instance_of(User).to receive(:icn).and_return('123498767V234859')
            allow_any_instance_of(Auth::ClientCredentials::Service).to receive(:get_token).and_return('fake_token')
          end

          context 'third party' do
            let(:expiration_date) { Time.zone.now }

            before do
              allow_any_instance_of(ActiveSupport::TimeZone).to receive(:now).and_return(expiration_date)
            end

            %w[THIRD_PARTY_VETERAN THIRD_PARTY_SURVIVING_DEPENDENT].each do |identification|
              it 'returns an expiration date' do
                fixture_path = Rails.root.join('modules', 'simple_forms_api', 'spec', 'fixtures', 'form_json',
                                               'vba_21_0966.json')
                data = JSON.parse(fixture_path.read)
                data['preparer_identification'] = identification

                post '/simple_forms_api/v1/simple_forms', params: data

                parsed_response_body = JSON.parse(response.body)
                parsed_expiration_date = Time.zone.parse(parsed_response_body['expiration_date'])
                expect(parsed_expiration_date.to_s).to eq (expiration_date + 1.year).to_s
              end
            end
          end
        end

        context 'unauthenticated' do
          let(:expiration_date) { Time.zone.now }

          before do
            allow_any_instance_of(ActiveSupport::TimeZone).to receive(:now).and_return(expiration_date)
          end

          it 'returns an expiration date' do
            fixture_path = Rails.root.join('modules', 'simple_forms_api', 'spec', 'fixtures', 'form_json',
                                           'vba_21_0966.json')
            data = JSON.parse(fixture_path.read)

            post '/simple_forms_api/v1/simple_forms', params: data

            parsed_response_body = JSON.parse(response.body)
            parsed_expiration_date = Time.zone.parse(parsed_response_body['expiration_date'])
            expect(parsed_expiration_date.to_s).to eq (expiration_date + 1.year).to_s
          end
        end
      end

      context 'request with attached documents' do
        it 'appends the attachments to the 40-0247 PDF' do
          fixture_path = Rails.root.join('modules', 'simple_forms_api', 'spec', 'fixtures', 'form_json',
                                         'vba_40_0247_with_supporting_document.json')
          pdf_path = Rails.root.join('spec', 'fixtures', 'files', 'doctors-note.pdf')
          data = JSON.parse(fixture_path.read)
          attachment = double
          allow(attachment).to receive(:to_pdf).and_return(pdf_path)

          expect(PersistentAttachment).to receive(:where).with(guid: ['a-random-uuid']).and_return([attachment])

          post '/simple_forms_api/v1/simple_forms', params: data

          expect(response).to have_http_status(:ok)
        end

        it 'appends the attachments to the 40-10007 PDF' do
          fixture_path = Rails.root.join('modules', 'simple_forms_api', 'spec', 'fixtures', 'form_json',
                                         'vba_40_10007_with_supporting_document.json')
          pdf_path = Rails.root.join('spec', 'fixtures', 'files', 'doctors-note.pdf')
          data = JSON.parse(fixture_path.read)
          attachment = double
          allow(attachment).to receive(:to_pdf).and_return(pdf_path)
          expect(PersistentAttachment).to receive(:where).with(guid: ['a-random-uuid']).and_return([attachment])
          post '/simple_forms_api/v1/simple_forms', params: data
          expect(response).to have_http_status(:ok)
        end
      end

      context 'LOA3 authenticated' do
        before do
          sign_in
          allow_any_instance_of(User).to receive(:icn).and_return('123498767V234859')
          allow_any_instance_of(Auth::ClientCredentials::Service).to receive(:get_token).and_return('fake_token')
        end

        it 'stamps the LOA3 text on the PDF' do
          fixture_path = Rails.root.join('modules', 'simple_forms_api', 'spec', 'fixtures', 'form_json',
                                         'vba_21_4142.json')
          data = JSON.parse(fixture_path.read)

          allow(SimpleFormsApiSubmission::MetadataValidator).to receive(:validate)
          expect_any_instance_of(SimpleFormsApi::PdfFiller).to receive(:generate).with(3)

          post '/simple_forms_api/v1/simple_forms', params: data
        end
      end

      context 'transliterating fields' do
        context 'transliteration succeeds' do
          it 'responds with ok' do
            fixture_path = Rails.root.join('modules', 'simple_forms_api', 'spec', 'fixtures', 'form_json',
                                           'form_with_accented_chars_21_0966.json')
            data = JSON.parse(fixture_path.read)

            post '/simple_forms_api/v1/simple_forms', params: data

            expect(response).to have_http_status(:ok)
          end
        end

        context 'transliteration fails' do
          it 'responds with an error' do
            fixture_path = Rails.root.join('modules', 'simple_forms_api', 'spec', 'fixtures', 'form_json',
                                           'form_with_non_latin_chars_21_0966.json')
            data = JSON.parse(fixture_path.read)

            post '/simple_forms_api/v1/simple_forms', params: data

            expect(response).to have_http_status(:error)
            expect(response.body).to include('not compatible with the Windows-1252 character set')
          end
        end
      end
    end

    context 'going to Lighthouse Benefits Claims API' do
      before do
        allow(Common::VirusScan).to receive(:scan).and_return(true)
        VCR.insert_cassette('lighthouse/benefits_claims/intent_to_file/404_response')
        VCR.insert_cassette('lighthouse/benefits_claims/intent_to_file/200_response_pension')
        VCR.insert_cassette('lighthouse/benefits_claims/intent_to_file/200_response_survivor')
        VCR.insert_cassette('lighthouse/benefits_claims/intent_to_file/create_compensation_200_response')
      end

      after do
        VCR.eject_cassette('lighthouse/benefits_claims/intent_to_file/404_response')
        VCR.eject_cassette('lighthouse/benefits_claims/intent_to_file/200_response_pension')
        VCR.eject_cassette('lighthouse/benefits_claims/intent_to_file/200_response_survivor')
        VCR.eject_cassette('lighthouse/benefits_claims/intent_to_file/create_compensation_200_response')
      end

      context 'authenticated' do
        before do
          sign_in
          allow_any_instance_of(User).to receive(:icn).and_return('123498767V234859')
          allow_any_instance_of(Auth::ClientCredentials::Service).to receive(:get_token).and_return('fake_token')
        end

        context 'request with intent to file' do
          context 'veteran' do
            it 'makes the request with an intent to file' do
              fixture_path = Rails.root.join('modules', 'simple_forms_api', 'spec', 'fixtures', 'form_json',
                                             'vba_21_0966-min.json')
              data = JSON.parse(fixture_path.read)
              data['preparer_identification'] = 'VETERAN'

              post '/simple_forms_api/v1/simple_forms', params: data

              expect(response).to have_http_status(:ok)
            end
          end
        end
      end
    end

    describe 'failed requests scrub PII from error messages' do
      describe 'unhandled form' do
        it 'makes the request and expects a failure' do
          fixture_path = Rails.root.join('modules', 'simple_forms_api', 'spec', 'fixtures', 'form_json',
                                         'form_with_dangerous_characters_unhandled.json')
          data = JSON.parse(fixture_path.read)

          post '/simple_forms_api/v1/simple_forms', params: data

          expect(response).to have_http_status(:error)
          expect(response.body).to include('something has gone wrong with your form')

          exception = JSON.parse(response.body)['errors'][0]['meta']['exception']
          expect(exception).not_to include(data.dig('veteran', 'ssn')&.[](0..2))
          expect(exception).not_to include(data.dig('veteran', 'ssn')&.[](3..4))
          expect(exception).not_to include(data.dig('veteran', 'ssn')&.[](5..8))
          expect(exception).not_to include(data.dig('veteran', 'address', 'postal_code')&.[](0..4))
        end
      end

      describe '21-4142' do
        it 'makes the request and expects a failure' do
          fixture_path = Rails.root.join('modules', 'simple_forms_api', 'spec', 'fixtures', 'form_json',
                                         'form_with_dangerous_characters_21_4142.json')
          data = JSON.parse(fixture_path.read)

          post '/simple_forms_api/v1/simple_forms', params: data

          expect(response).to have_http_status(:error)
          # 'unexpected token at' gets mangled by our scrubbing but this indicates that we're getting the right message
          expect(response.body).to include('unexpected ken at')

          exception = JSON.parse(response.body)['errors'][0]['meta']['exception']
          expect(exception).not_to include(data.dig('veteran', 'ssn')&.[](0..2))
          expect(exception).not_to include(data.dig('veteran', 'ssn')&.[](3..4))
          expect(exception).not_to include(data.dig('veteran', 'ssn')&.[](5..8))
          expect(exception).not_to include(data.dig('veteran', 'address', 'street'))
          expect(exception).not_to include(data.dig('veteran', 'address', 'street2'))
          expect(exception).not_to include(data.dig('veteran', 'address', 'street3'))
        end
      end

      describe '21-10210' do
        it 'makes the request and expects a failure' do
          fixture_path = Rails.root.join('modules', 'simple_forms_api', 'spec', 'fixtures', 'form_json',
                                         'form_with_dangerous_characters_21_10210.json')
          data = JSON.parse(fixture_path.read)

          post '/simple_forms_api/v1/simple_forms', params: data

          expect(response).to have_http_status(:error)
          # 'unexpected token at' gets mangled by our scrubbing but this indicates that we're getting the right message
          expect(response.body).to include('unexpected token t')

          exception = JSON.parse(response.body)['errors'][0]['meta']['exception']
          expect(exception).not_to include(data['veteran_ssn']&.[](0..2))
          expect(exception).not_to include(data['veteran_ssn']&.[](3..4))
          expect(exception).not_to include(data['veteran_ssn']&.[](5..8))
          expect(exception).not_to include(data['claimant_ssn']&.[](0..2))
          expect(exception).not_to include(data['claimant_ssn']&.[](3..4))
          expect(exception).not_to include(data['claimant_ssn']&.[](5..8))
        end
      end

      describe '26-4555' do
        it 'makes the request and expects a failure' do
          skip 'restore this test when we release the form to production'

          fixture_path = Rails.root.join('modules', 'simple_forms_api', 'spec', 'fixtures', 'form_json',
                                         'form_with_dangerous_characters_26_4555.json')
          data = JSON.parse(fixture_path.read)

          post '/simple_forms_api/v1/simple_forms', params: data

          expect(response).to have_http_status(:error)
          expect(response.body).to include('unexpected token at')

          exception = JSON.parse(response.body)['errors'][0]['meta']['exception']
          expect(exception).not_to include(data.dig('veteran', 'ssn')&.[](0..2))
          expect(exception).not_to include(data.dig('veteran', 'ssn')&.[](3..4))
          expect(exception).not_to include(data.dig('veteran', 'ssn')&.[](5..8))
          expect(exception).not_to include(data.dig('veteran', 'address', 'postal_code')&.[](0..4))
        end
      end

      describe '21P-0847' do
        it 'makes the request and expects a failure' do
          fixture_path = Rails.root.join('modules', 'simple_forms_api', 'spec', 'fixtures', 'form_json',
                                         'form_with_dangerous_characters_21P_0847.json')
          data = JSON.parse(fixture_path.read)

          post '/simple_forms_api/v1/simple_forms', params: data

          expect(response).to have_http_status(:error)
          # 'unexpected token at' gets mangled by our scrubbing but this indicates that we're getting the right message
          expect(response.body).to include('unexpected token t')

          exception = JSON.parse(response.body)['errors'][0]['meta']['exception']
          expect(exception).not_to include(data['preparer_ssn']&.[](0..2))
          expect(exception).not_to include(data['preparer_ssn']&.[](3..4))
          expect(exception).not_to include(data['preparer_ssn']&.[](5..8))
          expect(exception).not_to include(data.dig('preparer_address', 'postal_code')&.[](0..4))
          expect(exception).not_to include(data['veteran_ssn']&.[](0..2))
          expect(exception).not_to include(data['veteran_ssn']&.[](3..4))
          expect(exception).not_to include(data['veteran_ssn']&.[](5..8))
        end
      end

      describe '21-0845' do
        it 'makes the request and expects a failure' do
          fixture_path = Rails.root.join('modules', 'simple_forms_api', 'spec', 'fixtures', 'form_json',
                                         'form_with_dangerous_characters_21_0845.json')
          data = JSON.parse(fixture_path.read)

          post '/simple_forms_api/v1/simple_forms', params: data

          expect(response).to have_http_status(:error)
          # 'unexpected token at' gets mangled by our scrubbing but this indicates that we're getting the right message
          expect(response.body).to include('unexpected token t')

          exception = JSON.parse(response.body)['errors'][0]['meta']['exception']
          expect(exception).not_to include(data.dig('authorizer_address', 'postal_code')&.[](0..4))
          expect(exception).not_to include(data['veteran_ssn']&.[](0..2))
          expect(exception).not_to include(data['veteran_ssn']&.[](3..4))
          expect(exception).not_to include(data['veteran_ssn']&.[](5..8))
        end
      end
    end
  end

  describe '#submit_supporting_documents' do
    it 'renders the attachment as json' do
      clamscan = double(safe?: true)
      allow(Common::VirusScan).to receive(:scan).and_return(clamscan)
      file = fixture_file_upload('doctors-note.gif')

      # Define data for both form IDs
      data_sets = [
        { form_id: '40-0247', file: },
        { form_id: '40-10007', file: }
      ]

      data_sets.each do |data|
        expect do
          post '/simple_forms_api/v1/simple_forms/submit_supporting_documents', params: data
        end.to change(PersistentAttachment, :count).by(1)

        expect(response).to have_http_status(:ok)
        resp = JSON.parse(response.body)
        expect(resp['data']['attributes'].keys.sort).to eq(%w[confirmation_code name size])
        expect(PersistentAttachment.last).to be_a(PersistentAttachments::MilitaryRecords)
      end
    end
  end

  describe '#get_intents_to_file' do
    before do
      VCR.insert_cassette('lighthouse/benefits_claims/intent_to_file/404_response')
      VCR.insert_cassette('lighthouse/benefits_claims/intent_to_file/404_response_pension')
      VCR.insert_cassette('lighthouse/benefits_claims/intent_to_file/404_response_survivor')
      sign_in
      allow_any_instance_of(User).to receive(:icn).and_return('123498767V234859')
      allow_any_instance_of(Auth::ClientCredentials::Service).to receive(:get_token).and_return('fake_token')
    end

    after do
      VCR.eject_cassette('lighthouse/benefits_claims/intent_to_file/404_response')
      VCR.eject_cassette('lighthouse/benefits_claims/intent_to_file/404_response_pension')
      VCR.eject_cassette('lighthouse/benefits_claims/intent_to_file/404_response_survivor')
    end

    describe 'no intents on file' do
      it 'returns no intents' do
        get '/simple_forms_api/v1/simple_forms/get_intents_to_file'

        parsed_response = JSON.parse(response.body)
        expect(parsed_response['compensation_intent']).to eq nil
        expect(parsed_response['pension_intent']).to eq nil
        expect(parsed_response['survivor_intent']).to eq nil
        expect(response).to have_http_status(:ok)
      end
    end

    describe 'compensation intent on file' do
      before do
        VCR.insert_cassette('lighthouse/benefits_claims/intent_to_file/200_response')
      end

      after do
        VCR.eject_cassette('lighthouse/benefits_claims/intent_to_file/200_response')
      end

      it 'returns a compensation intent' do
        get '/simple_forms_api/v1/simple_forms/get_intents_to_file'

        parsed_response = JSON.parse(response.body)
        expect(parsed_response['compensation_intent']['type']).to eq 'compensation'
        expect(parsed_response['pension_intent']).to eq nil
        expect(parsed_response['survivor_intent']).to eq nil
        expect(response).to have_http_status(:ok)
      end
    end

    describe 'pension intent on file' do
      before do
        VCR.insert_cassette('lighthouse/benefits_claims/intent_to_file/200_response_pension')
      end

      after do
        VCR.eject_cassette('lighthouse/benefits_claims/intent_to_file/200_response_pension')
      end

      it 'returns a pension intent' do
        get '/simple_forms_api/v1/simple_forms/get_intents_to_file'

        parsed_response = JSON.parse(response.body)
        expect(parsed_response['compensation_intent']).to eq nil
        expect(parsed_response['pension_intent']['type']).to eq 'pension'
        expect(parsed_response['survivor_intent']).to eq nil
        expect(response).to have_http_status(:ok)
      end
    end

    describe 'both intents on file' do
      before do
        VCR.insert_cassette('lighthouse/benefits_claims/intent_to_file/200_response')
        VCR.insert_cassette('lighthouse/benefits_claims/intent_to_file/200_response_pension')
      end

      after do
        VCR.eject_cassette('lighthouse/benefits_claims/intent_to_file/200_response')
        VCR.eject_cassette('lighthouse/benefits_claims/intent_to_file/200_response_pension')
      end

      it 'returns a pension intent' do
        get '/simple_forms_api/v1/simple_forms/get_intents_to_file'

        parsed_response = JSON.parse(response.body)
        expect(parsed_response['compensation_intent']['type']).to eq 'compensation'
        expect(parsed_response['pension_intent']['type']).to eq 'pension'
        expect(parsed_response['survivor_intent']).to eq nil
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe 'email confirmations' do
    let(:confirmation_number) { 'some_confirmation_number' }

    describe '21_4142' do
      let(:data) do
        fixture_path = Rails.root.join(
          'modules', 'simple_forms_api', 'spec', 'fixtures', 'form_json', 'vba_21_4142.json'
        )
        JSON.parse(fixture_path.read)
      end

      it 'successful submission' do
        allow(VANotify::EmailJob).to receive(:perform_async)
        allow_any_instance_of(SimpleFormsApi::V1::UploadsController)
          .to receive(:upload_pdf_to_benefits_intake).and_return([200, confirmation_number])

        post '/simple_forms_api/v1/simple_forms', params: data

        expect(response).to have_http_status(:ok)

        expect(VANotify::EmailJob).to have_received(:perform_async).with(
          'veteran.surname@address.com',
          'form21_4142_confirmation_email_template_id',
          {
            'first_name' => 'VETERAN',
            'date_submitted' => Time.zone.today.strftime('%B %d, %Y'),
            'confirmation_number' => confirmation_number
          }
        )
      end

      it 'unsuccessful submission' do
        allow(VANotify::EmailJob).to receive(:perform_async)
        allow_any_instance_of(SimpleFormsApi::V1::UploadsController)
          .to receive(:upload_pdf_to_benefits_intake).and_return([500, confirmation_number])

        post '/simple_forms_api/v1/simple_forms', params: data

        expect(response).to have_http_status(:error)

        expect(VANotify::EmailJob).not_to have_received(:perform_async)
      end
    end

    describe '21_10210' do
      let(:data) do
        fixture_path = Rails.root.join(
          'modules', 'simple_forms_api', 'spec', 'fixtures', 'form_json', 'vba_21_10210.json'
        )
        JSON.parse(fixture_path.read)
      end

      it 'successful submission' do
        allow(VANotify::EmailJob).to receive(:perform_async)
        allow_any_instance_of(SimpleFormsApi::V1::UploadsController)
          .to receive(:upload_pdf_to_benefits_intake).and_return([200, confirmation_number])

        post '/simple_forms_api/v1/simple_forms', params: data

        expect(response).to have_http_status(:ok)

        expect(VANotify::EmailJob).to have_received(:perform_async).with(
          'my.long.email.address@email.com',
          'form21_10210_confirmation_email_template_id',
          {
            'first_name' => 'JACK',
            'date_submitted' => Time.zone.today.strftime('%B %d, %Y'),
            'confirmation_number' => confirmation_number
          }
        )
      end

      it 'unsuccessful submission' do
        allow(VANotify::EmailJob).to receive(:perform_async)
        allow_any_instance_of(SimpleFormsApi::V1::UploadsController)
          .to receive(:upload_pdf_to_benefits_intake).and_return([500, confirmation_number])

        post '/simple_forms_api/v1/simple_forms', params: data

        expect(response).to have_http_status(:error)

        expect(VANotify::EmailJob).not_to have_received(:perform_async)
      end
    end

    describe '21p_0847' do
      let(:data) do
        fixture_path = Rails.root.join(
          'modules',
          'simple_forms_api',
          'spec',
          'fixtures',
          'form_json',
          'vba_21p_0847.json'
        )
        JSON.parse(fixture_path.read)
      end

      it 'successful submission' do
        allow(VANotify::EmailJob).to receive(:perform_async)

        allow_any_instance_of(
          SimpleFormsApi::V1::UploadsController
        ).to receive(
          :upload_pdf_to_benefits_intake
        ).and_return([200, confirmation_number])

        post '/simple_forms_api/v1/simple_forms', params: data

        expect(response).to have_http_status(:ok)

        expect(VANotify::EmailJob).to have_received(:perform_async).with(
          'preparer_address@email.com',
          'form21p_0847_confirmation_email_template_id',
          {
            'first_name' => 'ARTHUR',
            'date_submitted' => Time.zone.today.strftime('%B %d, %Y'),
            'confirmation_number' => confirmation_number
          }
        )
      end

      it 'unsuccessful submission' do
        allow(VANotify::EmailJob).to receive(:perform_async)

        allow_any_instance_of(
          SimpleFormsApi::V1::UploadsController
        ).to receive(
          :upload_pdf_to_benefits_intake
        ).and_return([500, confirmation_number])

        post '/simple_forms_api/v1/simple_forms', params: data

        expect(response).to have_http_status(:error)

        expect(VANotify::EmailJob).not_to have_received(:perform_async)
      end
    end

    describe '21_0972' do
      let(:data) do
        fixture_path = Rails.root.join(
          'modules', 'simple_forms_api', 'spec', 'fixtures', 'form_json', 'vba_21_0972.json'
        )
        JSON.parse(fixture_path.read)
      end

      it 'successful submission' do
        allow(VANotify::EmailJob).to receive(:perform_async)
        allow_any_instance_of(SimpleFormsApi::V1::UploadsController)
          .to receive(:upload_pdf_to_benefits_intake).and_return([200, confirmation_number])

        post '/simple_forms_api/v1/simple_forms', params: data

        expect(response).to have_http_status(:ok)

        expect(VANotify::EmailJob).to have_received(:perform_async).with(
          'preparer@email.com',
          'form21_0972_confirmation_email_template_id',
          {
            'first_name' => 'PREPARE',
            'date_submitted' => Time.zone.today.strftime('%B %d, %Y'),
            'confirmation_number' => confirmation_number
          }
        )
      end

      it 'unsuccessful submission' do
        allow(VANotify::EmailJob).to receive(:perform_async)
        allow_any_instance_of(SimpleFormsApi::V1::UploadsController)
          .to receive(:upload_pdf_to_benefits_intake).and_return([500, confirmation_number])

        post '/simple_forms_api/v1/simple_forms', params: data

        expect(response).to have_http_status(:error)

        expect(VANotify::EmailJob).not_to have_received(:perform_async)
      end
    end
  end
end
