require "spec_helper"

describe CFoundry::UAAClient do
  let(:target) { "https://uaa.example.com" }
  let(:uaa) { CFoundry::UAAClient.new(target) }

  shared_examples "UAA wrapper" do
    it "converts UAA errors to CFoundry equivalents" do
      mock(uaa).wrap_uaa_errors { nil }
      subject
    end
  end

  describe '#prompts' do
    subject { uaa.prompts }

    include_examples "UAA wrapper"

    # GET (target)/login
    it "receives the prompts from /login" do
      stub_request(:get, "#{target}/login").to_return :status => 200,
        :headers => {'Content-Type' => 'application/json'},
        :body => <<EOF
          {
            "timestamp": "2012-11-08T13:32:18+0000",
            "commit_id": "ebbf817",
            "app": {
              "version": "1.2.6",
              "artifact": "cloudfoundry-identity-uaa",
              "description": "User Account and Authentication Service",
              "name": "UAA"
            },
            "prompts": {
              "username": [
                "text",
                "Email"
              ],
              "password": [
                "password",
                "Password"
              ]
            }
          }
EOF

      expect(subject).to eq(
        :username => ["text", "Email"],
        :password => ["password", "Password"])
    end
  end

  describe '#authorize' do
    let(:username) { "foo@bar.com" }
    let(:password) { "test" }
    let(:state) { 'somestate' }
    let(:redirect_uri) { 'https://uaa.cloudfoundry.com/redirect/vmc' }

    subject { uaa.authorize(:username => username, :password => password) }

    before(:each) do
      any_instance_of(CF::UAA::TokenIssuer, :random_state => state)
    end

    include_examples "UAA wrapper"

    it 'returns the token on successful authentication' do
      stub_request(
        :post,
        "#{target}/oauth/authorize"
      ).with(
        :query => {
          "client_id" => uaa.client_id,
          "redirect_uri" => redirect_uri,
          'response_type' => 'token',
          'state' => state,
        }
      ).to_return(
        :status => 302,
        :headers => {
          'Location' => "#{redirect_uri}#access_token=bar&token_type=foo&fizz=buzz&foo=bar&state=#{state}"
        }
      )

      expect(subject).to eq "foo bar"
    end

    context 'when authorization fails' do
      context 'in the expected way' do
        it 'raises a CFoundry::Denied error' do
          stub_request(:post, "#{target}/oauth/authorize").with(
            :query => {
              "client_id" => uaa.client_id,
              "redirect_uri" => redirect_uri,
              'response_type' => 'token',
              'state' => state,
            }
          ).to_return(
            :status => 401,
            :body => '{ "error": "some_error", "error_description": "some description" }'
          )

          expect { subject }.to raise_error(CFoundry::Denied, "401: Authorization failed")
        end
      end

      context 'in an unexpected way' do
        it 'raises a CFoundry::Denied error' do
          any_instance_of(CF::UAA::TokenIssuer) do |token_issuer|
            stub(token_issuer).implicit_grant_with_creds(anything) { raise CF::UAA::BadResponse.new("no_status_code") }
          end
          expect { subject }.to raise_error(CFoundry::Denied, "400: Authorization failed")
        end
      end
    end
  end

  describe '#users' do
    subject { uaa.users }

    it 'requests /Users' do
      req = stub_request(:get, "#{target}/Users").to_return(
        :headers => {'Content-Type' => 'application/json'},
        :body => '{ "resources": [] }')
      expect(subject).to eq({'resources' => []})
      expect(req).to have_been_requested
    end
  end

  describe '#change_password' do
    let(:guid) { "foo-bar-baz" }
    let(:old) { "old-pass" }
    let(:new) { "new-pass" }

    subject { uaa.change_password(guid, new, old) }

    include_examples "UAA wrapper"

    it 'sends a password change request' do
      req = stub_request(
        :put,
        "#{target}/Users/#{guid}/password"
      ).with(
        :headers => {
          "Content-Type" => "application/json;charset=utf-8",
          "Accept" => "application/json;charset=utf-8"
        }
      ).to_return(
        :status => 200,
        :headers => {'Content-Type' => 'application/json'},
        :body => '{ "status": "ok", "message": "password_updated" }'
      )

      subject

      expect(req).to have_been_requested
    end
  end

  describe '#password_score' do
    let(:password) { "password" }
    let(:response) { MultiJson.encode({}) }

    subject { uaa.password_score(password) }

    include_examples "UAA wrapper"

    before do
      @request = stub_request(:post, "#{target}/password/score").with(
        :body => 'password=password',
        :headers => {
          'Accept' => 'application/json;charset=utf-8',
          'Content-Type' => 'application/x-www-form-urlencoded;charset=utf-8'
        }
      ).to_return(
        :status => 200,
        :headers => {'Content-Type' => 'application/json'},
        :body => response
      )
    end

    it 'sends a password change request' do
      subject
      expect(@request).to have_been_requested
    end

    context 'when the score is 0 and the required is 0' do
      let(:response) { MultiJson.encode "score" => 0, "requiredScore" => 0 }
      it { should == :good }
    end

    context 'when the score is less than the required core' do
      let(:response) { MultiJson.encode "score" => 1, "requiredScore" => 5 }
      it { should == :weak }
    end

    context 'and the score is equal to the required score' do
      let(:response) { MultiJson.encode "score" => 5, "requiredScore" => 5 }
      it { should == :good }
    end

    context 'and the score is greater than the required score' do
      let(:response) { MultiJson.encode "score" => 6, "requiredScore" => 5 }
      it { should == :good }
    end

    context 'and the score is 10' do
      let(:response) { MultiJson.encode "score" => 10, "requiredScore" => 5 }
      it { should == :strong }
    end

    context 'and the score is 10' do
      let(:response) { MultiJson.encode "score" => 10, "requiredScore" => 10 }
      it { should == :strong }
    end

    context 'and the score is invalid' do
      let(:response) { MultiJson.encode "score" => 11, "requiredScore" => 5 }
      it { should == :weak }
    end
  end

  describe "#add_user" do
    let(:email) { 'test@test.com' }
    let(:password) { 'secret' }

    subject { uaa.add_user(email, password) }

    context 'with valid data' do
      it "should add a user" do
        req =
          stub_request(:post, "https://uaa.example.com/Users").with(
            :body =>
              { :userName => email,
                :emails => [{ :value => email }],
                :password => password,
                :name => { :givenName => email, :familyName => email }
              }
          ).to_return(
            :status => 200,
            :body => '{ "id" : "id" }',
            :headers => { "Content-Type" => 'application/json' }
          )

        expect(subject).to eq({"id" => "id"})
        expect(req).to have_been_requested
      end
    end
  end

  describe "#wrap_uaa_errors" do
    subject { uaa.send(:wrap_uaa_errors) { raise error } }

    context "when the block raises CF::UAA::BadResponse" do
      let(:error) { CF::UAA::BadResponse }

      it "raises CFoundry::BadResponse" do
        expect { subject }.to raise_exception(CFoundry::BadResponse)
      end
    end

    context "when the block raises CF::UAA::NotFound" do
      let(:error) { CF::UAA::NotFound }

      it "raises CFoundry::NotFound" do
        expect { subject }.to raise_exception(CFoundry::NotFound)
      end
    end

    context "when the block raises CF::UAA::InvalidToken" do
      let(:error) { CF::UAA::InvalidToken }

      it "raises CFoundry::Denied" do
        expect { subject }.to raise_exception(CFoundry::Denied)
      end
    end

    context "when the block raises CF::UAA::TargetError" do
      let(:error) { CF::UAA::TargetError.new({ "error" => "foo", "error_description" => "bar" }) }

      it "raises CFoundry::UAAError" do
        expect { subject }.to raise_exception(CFoundry::UAAError, "foo: bar")
      end
    end
  end
end