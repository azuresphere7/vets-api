# frozen_string_literal: true

require 'rails_helper'
require_relative '../../rails_helper'
require 'claims_api/v2/disability_compensation_benefits_documents_uploader'

RSpec.describe ClaimsApi::V2::DisabilityCompensationBenefitsDocumentsUploader, type: :job do
  subject { described_class }

  before do
    Sidekiq::Job.clear_all
    stub_claims_api_auth_token
    allow(Flipper).to receive(:enabled?).with(:claims_load_testing).and_return false
  end

  let(:user) { FactoryBot.create(:user, :loa3) }

  let(:auth_headers) do
    EVSS::DisabilityCompensationAuthHeaders.new(user).add_headers(EVSS::AuthHeaders.new(user).to_h)
  end

  let(:claim_date) { (Time.zone.today - 1.day).to_s }
  let(:anticipated_separation_date) { 2.days.from_now.strftime('%m-%d-%Y') }

  let(:form_data) do
    temp = Rails.root.join('modules', 'claims_api', 'spec', 'fixtures', 'v2', 'veterans', 'disability_compensation',
                           'form_526_json_api.json').read
    temp = JSON.parse(temp)
    attributes = temp['data']['attributes']
    attributes['claimDate'] = claim_date
    attributes['serviceInformation']['federalActivation']['anticipatedSeparationDate'] = anticipated_separation_date

    temp['data']['attributes']
  end

  let(:claim) do
    claim = create(:auto_established_claim, evss_id: '12345')
    claim.set_file_data!(
      Rack::Test::UploadedFile.new(
        Rails.root.join(*'/modules/claims_api/spec/fixtures/extras.pdf'.split('/')).to_s
      ),
      'docType',
      'description'
    )
    claim.status = ClaimsApi::AutoEstablishedClaim::PENDING
    claim.save!
    claim
  end

  context 'successful submission' do
    service = described_class.new

    it 'successful submit should add the job' do
      expect do
        subject.perform_async(claim.id)
      end.to change(subject.jobs, :size).by(1)
    end

    it 'the claim should still be established on a successful BD submission' do
      VCR.use_cassette('claims_api/bd/upload') do
        expect(claim.status).to eq('pending') # where we start

        service.perform(claim.id)

        claim.reload
        expect(claim.status).to eq('established') # where we end
      end
    end

    it 'submits successfully with BD' do
      expect_any_instance_of(ClaimsApi::BD).to receive(:upload).and_return true

      service.perform(claim.id)

      claim.reload
      expect(claim.uploader.blank?).to eq(false)
    end
  end

  describe 'when an errored job has exhausted its retries' do
    it 'logs to the ClaimsApi Logger' do
      error_msg = 'An error occurred from the BD Uploader Job'
      msg = { 'args' => [claim.id],
              'class' => subject,
              'error_message' => error_msg }

      described_class.within_sidekiq_retries_exhausted_block(msg) do
        expect(ClaimsApi::Logger).to receive(:log).with(
          'claims_api_retries_exhausted',
          record_id: claim.id,
          detail: "Job retries exhausted for #{subject}",
          error: error_msg
        )
      end
    end
  end
end
