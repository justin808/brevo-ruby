# encoding: utf-8
require 'spec_helper'

describe 'JSON compatibility' do
  let(:client) { Brevo::ApiClient.new(Brevo::Configuration.new) }

  it 'permits JSON 2 and 3 without admitting an untested future major version' do
    specification = Gem::Specification.load(File.expand_path('../brevo.gemspec', __dir__))
    requirement = specification.runtime_dependencies.find { |dependency| dependency.name == 'json' }.requirement

    %w[2.1.0 2.21.2 3.1.0].each do |version|
      expect(requirement.satisfied_by?(Gem::Version.new(version))).to be(true)
    end
    expect(requirement.satisfied_by?(Gem::Version.new('4.0.0'))).to be(false)
  end

  it 'serializes contact attributes and API field names without losing Unicode or false values' do
    contact = Brevo::CreateContact.new(
      :email => 'person@example.test',
      :attributes => { 'FIRSTNAME' => 'Zoë 🌊', 'ACTIVE' => false, 'COUNT' => 12 },
      :listIds => [3, 7],
      :updateEnabled => true
    )

    body = client.object_to_http_body(contact)
    expect(JSON.parse(body)).to eq(
      'email' => 'person@example.test',
      'attributes' => { 'FIRSTNAME' => 'Zoë 🌊', 'ACTIVE' => false, 'COUNT' => 12 },
      'listIds' => [3, 7], 'updateEnabled' => true
    )
  end

  it 'serializes empty lists and explicit null attributes on contact updates' do
    contact = Brevo::UpdateContact.new(:attributes => { 'NAME' => nil }, :listIds => [])
    expect(JSON.parse(client.object_to_http_body(contact))).to eq(
      'attributes' => { 'NAME' => nil }, 'listIds' => []
    )
  end

  it 'deserializes a successful contact response into the generated model' do
    response = double('response', :headers => { 'Content-Type' => 'application/json' }, :body => '{"id":123}')
    result = client.deserialize(response, 'CreateUpdateContactModel')
    expect(result).to be_a(Brevo::CreateUpdateContactModel)
    expect(result.id).to eq(123)
  end

  it 'preserves nested data, Unicode, booleans, nulls, and numbers in responses' do
    response = double('response', :headers => {}, :body => '{"name":"Zoë 🌊","items":[false,null,1.25]}')
    expect(client.deserialize(response, 'Object')).to eq(:name => 'Zoë 🌊', :items => [false, nil, 1.25])
  end

  it 'returns nil for an empty response' do
    response = double('response', :headers => {}, :body => '')
    expect(client.deserialize(response, 'Object')).to be_nil
  end

  it 'rejects malformed JSON instead of treating it as a successful model response' do
    response = double('response', :headers => {}, :body => '{"id":')
    expect { client.deserialize(response, 'CreateUpdateContactModel') }.to raise_error(JSON::ParserError)
  end

  it 'preserves HTTP error status and response body' do
    body = '{"code":"invalid_parameter","message":"Invalid email"}'
    response = Typhoeus::Response.new(:code => 400, :body => body, :headers => { 'Content-Type' => 'application/json' })
    request = instance_double(Typhoeus::Request, :run => response)
    allow(Typhoeus::Request).to receive(:new).and_return(request)

    expect { client.call_api(:post, '/contacts', :body => '{}') }.to raise_error(Brevo::ApiError) { |error|
      expect(error.code).to eq(400)
      expect(error.response_body).to eq(body)
    }
  end
end
