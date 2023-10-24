# frozen_string_literal: true

require 'bgs/form686c'

module BGS
  class SubmitForm686cEncryptedJob < Job
    class Invalid686cClaim < StandardError; end
    FORM_ID = '686C-674'
    include Sidekiq::Job
    include SentryLogging

    sidekiq_options retry: false

    def perform(user_uuid, icn, saved_claim_id, encrypted_vet_info) # rubocop:disable Metrics/MethodLength # Disabling until flipper removal in rescue
      vet_info = JSON.parse(KmsEncrypted::Box.new.decrypt(encrypted_vet_info))
      Rails.logger.info('BGS::SubmitForm686cJob running!', { user_uuid:, saved_claim_id:, icn: })
      in_progress_form = InProgressForm.find_by(form_id: FORM_ID, user_uuid:)
      in_progress_copy = in_progress_form_copy(in_progress_form)
      claim_data = normalize_names_and_addresses!(valid_claim_data(saved_claim_id, vet_info))
      user = generate_user_struct(vet_info['veteran_information'])

      BGS::Form686c.new(user).submit(claim_data)

      # If Form 686c job succeeds, then enqueue 674 job.
      claim = SavedClaim::DependencyClaim.find(saved_claim_id)
      BGS::SubmitForm674EncryptedJob.perform_async(user_uuid, icn, saved_claim_id, encrypted_vet_info, KmsEncrypted::Box.new.encrypt(user.to_h.to_json)) if claim.submittable_674? # rubocop:disable Layout/LineLength

      send_confirmation_email(user)
      in_progress_form&.destroy

      Rails.logger.info('BGS::SubmitForm686cJob succeeded!', { user_uuid:, saved_claim_id:, icn: })
    rescue => e
      Rails.logger.error('BGS::SubmitForm686cJob failed!', { user_uuid:, saved_claim_id:, icn:, error: e.message })
      log_message_to_sentry(e, :error, {}, { team: 'vfs-ebenefits' })
      salvage_save_in_progress_form(FORM_ID, user_uuid, in_progress_copy)
      if Flipper.enabled?(:dependents_central_submission)
        user_struct = generate_user_struct(vet_info['veteran_information'])
        CentralMail::SubmitCentralForm686cJob.perform_async(saved_claim_id, encrypted_vet_info,
                                                            KmsEncrypted::Box.new.encrypt(user_struct.to_h.to_json))
      else
        DependentsApplicationFailureMailer.build(user).deliver_now if user&.email.present? # rubocop:disable Style/IfInsideElse
      end
    end

    private

    def valid_claim_data(saved_claim_id, vet_info)
      claim = SavedClaim::DependencyClaim.find(saved_claim_id)

      claim.add_veteran_info(vet_info)

      raise Invalid686cClaim unless claim.valid?(:run_686_form_jobs)

      claim.formatted_686_data(vet_info)
    end

    def send_confirmation_email(user)
      return if user.va_profile_email.blank?

      VANotify::ConfirmationEmail.send(
        email_address: user.va_profile_email,
        template_id: Settings.vanotify.services.va_gov.template_id.form686c_confirmation_email,
        first_name: user&.first_name&.upcase,
        user_uuid_and_form_id: "#{user.uuid}_#{FORM_ID}"
      )
    end

    def generate_user_struct(vet_info)
      OpenStruct.new(
        first_name: vet_info['full_name']['first'],
        last_name: vet_info['full_name']['last'],
        middle_name: vet_info['full_name']['middle'],
        ssn: vet_info['ssn'],
        email: vet_info['email'],
        va_profile_email: vet_info['va_profile_email'],
        participant_id: vet_info['participant_id'],
        icn: vet_info['icn'],
        uuid: vet_info['uuid'],
        common_name: vet_info['common_name']
      )
    end
  end
end