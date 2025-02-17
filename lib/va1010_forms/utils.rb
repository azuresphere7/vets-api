# frozen_string_literal: true

require 'hca/configuration'
require 'hca/overrides_parser'

module VA1010Forms
  module Utils
    def es_submit(parsed_form, form_id)
      formatted = HCA::EnrollmentSystem.veteran_to_save_submit_form(parsed_form, @user, form_id)
      content = Gyoku.xml(formatted)
      submission = soap.build_request(:save_submit_form, message: content)
      response = perform(:post, '', submission.body)

      root = response.body.locate('S:Envelope/S:Body/submitFormResponse').first
      form_submission_id = root.locate('formSubmissionId').first.text.to_i

      {
        success: true,
        formSubmissionId: form_submission_id,
        timestamp: root.locate('timeStamp').first&.text || Time.now.getlocal.to_s
      }
    end

    def soap
      # Savon *seems* like it should be setting these things correctly
      # from what the docs say. Our WSDL file is weird, maybe?
      Savon.client(
        wsdl: HCA::Configuration::WSDL,
        env_namespace: :soap,
        element_form_default: :qualified,
        namespaces: {
          'xmlns:tns': 'http://va.gov/service/esr/voa/v1'
        },
        namespace: 'http://va.gov/schema/esr/voa/v1'
      )
    end

    def override_parsed_form(parsed_form)
      HCA::OverridesParser.new(parsed_form).override
    end
  end
end
