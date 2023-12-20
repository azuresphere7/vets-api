# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Lighthouse::PensionBenefitIntakeJob, uploader_helpers: true do
  stub_virus_scan
  let(:job) { described_class.new }
  let(:claim) { create(:pension_claim) }

  describe '#perform' do
    let(:service) { double('service') }
    let(:response) { double('response') }
    let(:pdf_path) { 'random/path/to/pdf' }

    before do
      allow(job).to receive(:process_pdf).and_return(pdf_path)

      allow(SavedClaim::Pension).to receive(:find).and_return(claim)
      allow(claim).to receive(:to_pdf).and_return(pdf_path)

      allow(BenefitsIntakeService::Service).to receive(:new).and_return(service)
      allow(service).to receive(:uuid)
      allow(service).to receive(:upload_form).and_return(response)
    end

    it 'submits the saved claim successfully' do
      doc = { file: pdf_path, file_name: 'pdf' }

      expect(claim).to receive(:to_pdf)
      expect(job).to receive(:process_pdf).with(pdf_path)
      expect(job).to receive(:generate_form_metadata_lh).once
      expect(service).to receive(:upload_form).with(
        main_document: doc, attachments: [], form_metadata: anything
      )
      expect(job).to receive(:check_success).with(response)

      expect(job).to receive(:cleanup_file_paths)

      job.perform(claim.id)
    end

    it 'is unable to find saved_claim_id' do
      allow(SavedClaim::Pension).to receive(:find).and_return(nil)

      expect(claim).not_to receive(:to_pdf)
      expect { job.perform(claim.id) }.to raise_error(
        Lighthouse::PensionBenefitIntakeJob::PensionBenefitIntakeError,
        "Unable to find SavedClaim::Pension #{claim.id}"
      )
    end
    # perform
  end

  describe '#process_pdf' do
    let(:service) { double('service') }
    let(:response) { double('response') }
    let(:pdf_path) { 'random/path/to/pdf' }

    before do
      allow(BenefitsIntakeService::Service).to receive(:new).and_return(service)
      allow(service).to receive(:validate_document).and_return(response)
    end

    it 'returns a datestamp pdf path' do
      run_count = 0
      allow_any_instance_of(CentralMail::DatestampPdf).to receive(:run) {
                                                            run_count += 1
                                                            pdf_path
                                                          }
      allow(response).to receive(:success?).and_return(true)

      new_path = job.process_pdf('test/path')

      expect(new_path).to eq(pdf_path)
      expect(run_count).to eq(2)
    end

    it 'raises an error on invalid document' do
      allow_any_instance_of(CentralMail::DatestampPdf).to receive(:run)
      allow(response).to receive(:success?).and_return(false)

      expect { job.process_pdf('test/path') }.to raise_error(
        Lighthouse::PensionBenefitIntakeJob::PensionBenefitIntakeError,
        "Invalid Document: #{response}"
      )
    end
    # process_pdf
  end

  describe '#generate_form_metadata_lh' do
    before do
      job.instance_variable_set(:@claim, claim)
    end

    it 'returns expected hash' do
      expect(job.generate_form_metadata_lh).to include(
        veteran_first_name: be_a(String),
        veteran_last_name: be_a(String),
        file_number: be_a(String),
        zip: be_a(String),
        doc_type: be_a(String),
        claim_date: be_a(ActiveSupport::TimeWithZone)
      )
    end
    # generate_form_metadata_lh
  end

  describe '#check_success' do
    let(:response) { double('response') }

    it 'sends a confirmation email on success' do
      job.instance_variable_set(:@claim, claim)
      allow(response).to receive(:success?).and_return(true)

      expect(claim).to receive(:send_confirmation_email)
      job.check_success(response)
    end

    it 'does not send an email on failure' do
      job.instance_variable_set(:@claim, claim)

      allow(response).to receive(:message).and_return('TEST RESPONSE')
      allow(response).to receive(:success?).and_return(false)

      expect(claim).not_to receive(:send_confirmation_email)
      expect { job.check_success(response) }.to raise_error(
        Lighthouse::PensionBenefitIntakeJob::PensionBenefitIntakeError,
        response.to_s
      )
    end
    # check_success
  end
  # Rspec.describe
end