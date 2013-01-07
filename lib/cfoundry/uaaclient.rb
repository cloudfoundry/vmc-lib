require "cfoundry/baseclient"
require 'uaa'

module CFoundry
  class UAAClient < BaseClient
    attr_accessor :target, :client_id, :redirect_uri, :token, :trace

    def initialize(
        target = "https://uaa.cloudfoundry.com",
            client_id = "vmc")
      @target = target
      @client_id = client_id
      @redirect_uri = "https://uaa.cloudfoundry.com/redirect/vmc"
      @token_issuer = CF::UAA::TokenIssuer.new(target, client_id)
    end

    def prompts
      symbolize_keys(CF::UAA::Misc.server(target)['prompts'])
    end

    def authorize(credentials)
      begin
        response = @token_issuer.implicit_grant_with_creds(credentials)
        "#{response.info['token_type']} #{response.info['access_token']}"
      rescue CF::UAA::BadResponse => e
        # Handle other types of bad responses?
        raise case e.message
                when 'status 401' then
                  CFoundry::Denied.new(401, 'Bad credentials')
                else
                  e
              end
      end
    end

    def users
      CF::UAA::Scim.new(target, token).query(:user)
    end

    def change_password(guid, new, old)
      CF::UAA::Scim.new(target, token).change_password(guid, new, old)
    end

    def password_score(password)
      response = CF::UAA::Misc.password_strength(target, password)

      required_score = response['requiredScore'] || 0
      case (response['score'] || 0)
        when 10 then
          :strong
        when required_score..9 then
          :good
        else
          :weak
      end
    end

    private

    def symbolize_keys(h)
      h.inject({}) { |memo, (k, v)| memo[k.to_sym] = v; memo }
    end

  end
end
