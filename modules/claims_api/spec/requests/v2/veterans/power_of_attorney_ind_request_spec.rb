# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../rails_helper'
require 'token_validation/v2/client'
require 'bgs_service/local_bgs'

RSpec.describe 'Power Of Attorney', type: :request do
  let(:veteran_id) { '1013062086V794840' }
  let(:appoint_individual_path) { "/services/claims/v2/veterans/#{veteran_id}/2122a" }
  let(:validate2122a_path) { "/services/claims/v2/veterans/#{veteran_id}/2122a/validate" }
  let(:scopes) { %w[system/claim.write system/claim.read] }
  let(:individual_poa_code) { 'A1H' }
  let(:organization_poa_code) { '083' }
  let(:bgs_poa) { { person_org_name: "#{individual_poa_code} name-here" } }
  let(:local_bgs) { ClaimsApi::LocalBGS }

  describe 'PowerOfAttorney' do
    before do
      Veteran::Service::Representative.create!(representative_id: '12345', poa_codes: [individual_poa_code],
                                               first_name: 'Abraham', last_name: 'Lincoln')
      Veteran::Service::Representative.create!(representative_id: '999999999999', poa_codes: [organization_poa_code],
                                               first_name: 'George', last_name: 'Washington')
    end

    describe 'appoint_individual' do
      let(:data) do
        {
          data: {
            attributes: {
              veteran: {
                address: {
                  addressLine1: '123',
                  city: 'city',
                  stateCode: 'OR',
                  country: 'US',
                  zipCode: '12345'
                }
              },
              representative: {
                poaCode: individual_poa_code,
                registrationNumber: '12345',
                type: 'ATTORNEY',
                address: {
                  addressLine1: '123',
                  city: 'city',
                  country: 'US',
                  zipCode: '12345'
                }
              }
            }
          }
        }
      end

      let(:claimant_data) do
        {
          data: {
            attributes: {
              veteran: {
                address: {
                  addressLine1: '123',
                  city: 'city',
                  stateCode: 'OR',
                  country: 'US',
                  zipCode: '12345'
                }
              },
              representative: {
                poaCode: individual_poa_code,
                registrationNumber: '12345',
                type: 'ATTORNEY',
                address: {
                  addressLine1: '123',
                  city: 'city',
                  stateCode: 'OR',
                  country: 'US',
                  zipCode: '12345'
                }
              },
              claimant: {
                claimantId: '1013062086V794840',
                address: {
                  addressLine1: '123',
                  city: 'city',
                  stateCode: 'OR',
                  country: 'US',
                  zipCode: '12345'
                },
                relationship: 'spouse'
              }
            }
          }
        }
      end

      context 'when a POA code isn\'t provided' do
        it 'returns a 422 error code' do
          mock_ccg(scopes) do |auth_header|
            data[:data][:attributes][:representative] = nil

            post appoint_individual_path, params: data.to_json, headers: auth_header
            expect(response).to have_http_status(:unprocessable_entity)
          end
        end
      end

      context 'CCG (Client Credentials Grant) flow' do
        context 'when provided' do
          context 'when valid' do
            it 'returns a 202' do
              VCR.use_cassette('claims_api/mpi/find_candidate/valid_icn_full') do
                mock_ccg(scopes) do |auth_header|
                  expect_any_instance_of(local_bgs).to receive(:find_poa_by_participant_id)
                    .and_return(bgs_poa)
                  allow_any_instance_of(local_bgs).to receive(:find_poa_history_by_ptcpnt_id)
                    .and_return({ person_poa_history: nil })

                  post appoint_individual_path, params: data.to_json, headers: auth_header
                  expect(response).to have_http_status(:accepted)
                end
              end
            end
          end

          context 'when not valid' do
            it 'returns a 401' do
              post appoint_individual_path, params: data.to_json, headers: { 'Authorization' => 'Bearer HelloWorld' }

              expect(response).to have_http_status(:unauthorized)
            end
          end

          context 'when claimant data is included' do
            shared_context 'claimant data setup' do
              before do
                allow_any_instance_of(local_bgs).to receive(:find_poa_by_participant_id).and_return(bgs_poa)
                allow_any_instance_of(local_bgs)
                  .to receive(:find_poa_history_by_ptcpnt_id).and_return({ person_poa_history: nil })
              end
            end

            context 'it is conditionally validated' do
              include_context 'claimant data setup'

              it 'returns a 202 when all conditionally required data is present' do
                mock_ccg(scopes) do |auth_header|
                  VCR.use_cassette('claims_api/mpi/find_candidate/valid_icn_full') do
                    post appoint_individual_path, params: claimant_data.to_json, headers: auth_header
                  end
                  expect(response).to have_http_status(:accepted)
                end
              end

              it 'returns a 422 if claimant.address.addressLine1 is not provided' do
                mock_ccg(scopes) do |auth_header|
                  claimant_data[:data][:attributes][:claimant][:address][:addressLine1] = nil
                  VCR.use_cassette('claims_api/mpi/find_candidate/valid_icn_full') do
                    post appoint_individual_path, params: claimant_data.to_json, headers: auth_header
                  end
                  expect(response).to have_http_status(:unprocessable_entity)
                  response_body = JSON.parse(response.body)
                  expect(response_body['errors'][0]['detail']).to eq(
                    "If claimant is present 'addressLine1' must be filled in"
                  )
                end
              end

              it 'returns a 422 if claimant.address.city is not provided' do
                mock_ccg(scopes) do |auth_header|
                  claimant_data[:data][:attributes][:claimant][:address][:city] = nil
                  VCR.use_cassette('claims_api/mpi/find_candidate/valid_icn_full') do
                    post appoint_individual_path, params: claimant_data.to_json, headers: auth_header
                  end
                  expect(response).to have_http_status(:unprocessable_entity)
                  response_body = JSON.parse(response.body)
                  expect(response_body['errors'][0]['detail']).to eq(
                    "If claimant is present 'city' must be filled in"
                  )
                end
              end

              it 'returns a 422 if claimant.address.stateCode is not provided' do
                mock_ccg(scopes) do |auth_header|
                  claimant_data[:data][:attributes][:claimant][:address][:stateCode] = nil
                  VCR.use_cassette('claims_api/mpi/find_candidate/valid_icn_full') do
                    post appoint_individual_path, params: claimant_data.to_json, headers: auth_header
                  end
                  expect(response).to have_http_status(:unprocessable_entity)
                  response_body = JSON.parse(response.body)
                  expect(response_body['errors'][0]['detail']).to eq(
                    "If claimant is present 'stateCode' must be filled in"
                  )
                end
              end

              it 'returns a 422 if claimant.address.country is not provided' do
                mock_ccg(scopes) do |auth_header|
                  claimant_data[:data][:attributes][:claimant][:address][:country] = nil
                  VCR.use_cassette('claims_api/mpi/find_candidate/valid_icn_full') do
                    post appoint_individual_path, params: claimant_data.to_json, headers: auth_header
                  end
                  expect(response).to have_http_status(:unprocessable_entity)
                  response_body = JSON.parse(response.body)
                  expect(response_body['errors'][0]['detail']).to eq(
                    "If claimant is present 'country' must be filled in"
                  )
                end
              end

              it 'returns a 422 if claimant.address.zipCode is not provided' do
                mock_ccg(scopes) do |auth_header|
                  claimant_data[:data][:attributes][:claimant][:address][:zipCode] = nil
                  VCR.use_cassette('claims_api/mpi/find_candidate/valid_icn_full') do
                    post appoint_individual_path, params: claimant_data.to_json, headers: auth_header
                  end
                  expect(response).to have_http_status(:unprocessable_entity)
                  response_body = JSON.parse(response.body)
                  expect(response_body['errors'][0]['detail']).to eq(
                    "If claimant is present 'zipCode' must be filled in"
                  )
                end
              end

              it 'returns a 422 if claimant.relationship is not provided' do
                VCR.use_cassette('claims_api/mpi/find_candidate/valid_icn_full') do
                  mock_ccg(scopes) do |auth_header|
                    claimant_data[:data][:attributes][:claimant][:relationship] = nil

                    post appoint_individual_path, params: claimant_data.to_json, headers: auth_header
                    expect(response).to have_http_status(:unprocessable_entity)
                    response_body = JSON.parse(response.body)
                    expect(response_body['errors'][0]['detail']).to eq(
                      "If claimant is present 'relationship' must be filled in"
                    )
                  end
                end
              end
            end
          end
        end
      end
    end

    describe 'validate2122a' do
      let(:data) do
        {
          data: {
            attributes: {
              veteran: {
                address: {
                  addressLine1: '123',
                  city: 'city',
                  country: 'US',
                  zipCode: '12345'
                }
              },
              representative: {
                poaCode: individual_poa_code,
                type: 'ATTORNEY',
                address: {
                  addressLine1: '123',
                  city: 'city',
                  country: 'US',
                  zipCode: '12345'
                }
              }
            }
          }
        }
      end

      context 'CCG (Client Credentials Grant) flow' do
        context 'when provided' do
          context 'when valid' do
            context 'when the request data is not a valid json object' do
              let(:data) { '123abc' }

              it 'returns a meaningful 422' do
                mock_ccg(%w[claim.write claim.read]) do |auth_header|
                  detail = 'The request body is not a valid JSON object: '

                  post validate2122a_path, params: data, headers: auth_header

                  response_body = JSON.parse(response.body)['errors'][0]

                  expect(response).to have_http_status(:unprocessable_entity)
                  expect(response_body['title']).to eq('Unprocessable entity')
                  expect(response_body['status']).to eq('422')
                  expect(response_body['detail']).to eq(detail)
                end
              end
            end

            context 'when the request data is a valid json object' do
              context 'when the Veteran ICN is not found in MPI' do
                it 'returns a meaningful 404' do
                  mock_ccg(%w[claim.write claim.read]) do |auth_header|
                    allow_any_instance_of(ClaimsApi::Veteran)
                      .to receive(:mpi_record?).and_return(false)

                    detail = "Unable to locate Veteran's ID/ICN in Master Person Index (MPI). " \
                             'Please submit an issue at ask.va.gov or call 1-800-MyVA411 (800-698-2411) for assistance.'

                    post validate2122a_path, params: { data: { attributes: nil } }.to_json, headers: auth_header

                    response_body = JSON.parse(response.body)['errors'][0]

                    expect(response).to have_http_status(:not_found)
                    expect(response_body['title']).to eq('Resource not found')
                    expect(response_body['status']).to eq('404')
                    expect(response_body['detail']).to eq(detail)
                  end
                end
              end

              context 'when the Veteran ICN is found in MPI' do
                context 'when the request data does not pass schema validation' do
                  let(:request_body) do
                    Rails.root.join('modules', 'claims_api', 'spec', 'fixtures', 'v2', 'veterans',
                                    'power_of_attorney', '2122a', 'invalid_schema.json').read
                  end

                  it 'returns a meaningful 422' do
                    mock_ccg(%w[claim.write claim.read]) do |auth_header|
                      detail = 'The property /representative did not contain the required key poaCode'

                      post validate2122a_path, params: request_body, headers: auth_header

                      response_body = JSON.parse(response.body)['errors'][0]

                      expect(response).to have_http_status(:unprocessable_entity)
                      expect(response_body['title']).to eq('Unprocessable entity')
                      expect(response_body['status']).to eq('422')
                      expect(response_body['detail']).to eq(detail)
                    end
                  end
                end

                context 'when the request data passes schema validation' do
                  context 'when no representatives have the provided POA code' do
                    let(:request_body) do
                      Rails.root.join('modules', 'claims_api', 'spec', 'fixtures', 'v2', 'veterans',
                                      'power_of_attorney', '2122a', 'invalid_poa.json').read
                    end

                    it 'returns a meaningful 404' do
                      mock_ccg(%w[claim.write claim.read]) do |auth_header|
                        detail = 'Could not find an Accredited Representative with registration number: 999999999999 ' \
                                 'and poa code: aaa'

                        post validate2122a_path, params: request_body, headers: auth_header
                        response_body = JSON.parse(response.body)['errors'][0]

                        expect(response).to have_http_status(:not_found)
                        expect(response_body['title']).to eq('Resource not found')
                        expect(response_body['status']).to eq('404')
                        expect(response_body['detail']).to eq(detail)
                      end
                    end
                  end

                  context 'when at least one representative has the provided POA code' do
                    let(:request_body) do
                      Rails.root.join('modules', 'claims_api', 'spec', 'fixtures', 'v2', 'veterans',
                                      'power_of_attorney', '2122a', 'valid.json').read
                    end

                    it 'returns a meaningful 200' do
                      mock_ccg(%w[claim.write claim.read]) do |auth_header|
                        post validate2122a_path, params: request_body, headers: auth_header

                        response_body = JSON.parse(response.body)['data']

                        expect(response).to have_http_status(:ok)
                        expect(response_body['type']).to eq('form/21-22a/validation')
                        expect(response_body['attributes']['status']).to eq('valid')
                      end
                    end
                  end

                  context 'when no claimantId is provided and other claimant data is present' do
                    let(:request_body) do
                      Rails.root.join('modules', 'claims_api', 'spec', 'fixtures', 'v2', 'veterans',
                                      'power_of_attorney', '2122a', 'valid.json').read
                    end

                    let(:claimant) do
                      {
                        email: 'lillian@disney.com',
                        relationship: 'Spouse',
                        address: {
                          addressLine1: '2688 S Camino Real',
                          city: 'Palm Springs',
                          stateCode: 'CA',
                          country: 'US',
                          zipCode: '92264'
                        },
                        phone: {
                          areaCode: '555',
                          phoneNumber: '5551337'
                        }
                      }
                    end
                    let(:error_msg) { "If claimant is present 'claimantId' must be filled in" }

                    it 'returns a meaningful 422' do
                      mock_ccg(%w[claim.write claim.read]) do |auth_header|
                        json = JSON.parse(request_body)
                        json['data']['attributes']['claimant'] = claimant
                        request_body = json.to_json
                        post validate2122a_path, params: request_body, headers: auth_header

                        response_body = JSON.parse(response.body)['errors'][0]
                        expect(response).to have_http_status(:unprocessable_entity)
                        expect(response_body['detail']).to eq(error_msg)
                      end
                    end
                  end
                end
              end
            end
          end
        end

        context 'when not valid' do
          it 'returns a 401' do
            post validate2122a_path, headers: { 'Authorization' => 'Bearer HelloWorld' }

            expect(response).to have_http_status(:unauthorized)
          end
        end
      end
    end
  end
end
