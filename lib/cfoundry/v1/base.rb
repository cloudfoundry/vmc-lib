require "multi_json"

require "cfoundry/baseclient"
require "cfoundry/uaaclient"

require "cfoundry/errors"

module CFoundry::V1
  class Base < CFoundry::BaseClient
    attr_accessor :target, :token, :proxy, :trace, :backtrace, :log

    def initialize(
        target = "https://api.cloudfoundry.com",
        token = nil)
      super
    end


    # The UAA used for this client.
    #
    # `false` if no UAA (legacy)
    def uaa
      return @uaa unless @uaa.nil?

      endpoint = info[:authorization_endpoint]
      return @uaa = false unless endpoint

      @uaa = CFoundry::UAAClient.new(endpoint)
      @uaa.trace = @trace
      @uaa.token = @token
      @uaa
    end


    # Cloud metadata
    def info
      get("info", nil => :json)
    end

    def system_services
      get("info", "services", nil => :json)
    end

    def system_runtimes
      get("info", "runtimes", nil => :json)
    end

    # Users
    def users
      get("users", nil => :json)
    end

    def create_user(payload)
      post(payload, "users", :json => nil)
    end

    def user(email)
      get("users", email, nil => :json)
    end

    def delete_user(email)
      delete("users", email, nil => :json)
      true
    end

    def update_user(email, payload)
      put(payload, "users", email, :json => nil)
    end

    def create_token(payload, email)
      post(payload, "users", email, "tokens", :json => :json)
    end

    # Applications
    def apps
      get("apps", nil => :json)
    end

    def create_app(payload)
      post(payload, "apps", :json => :json)
    end

    def app(name)
      get("apps", name, nil => :json)
    end

    def instances(name)
      get("apps", name, "instances", nil => :json)[:instances]
    end

    def crashes(name)
      get("apps", name, "crashes", nil => :json)[:crashes]
    end

    def files(name, instance, *path)
      get("apps", name, "instances", instance, "files", *path)
    end
    alias :file :files

    def update_app(name, payload)
      put(payload, "apps", name, :json => nil)
    end

    def delete_app(name)
      delete("apps", name)
      true
    end

    def stats(name)
      get("apps", name, "stats", nil => :json)
    end

    def check_resources(fingerprints)
      post(fingerprints, "resources", :json => :json)
    end

    def upload_app(name, zipfile, resources = [])
      payload = {
        :_method => "put",
        :resources => MultiJson.dump(resources),
        :application =>
          UploadIO.new(
            if zipfile.is_a? File
              zipfile
            elsif zipfile.is_a? String
              File.new(zipfile, "rb")
            end,
            "application/zip")
      }

      post(payload, "apps", name, "application")
    rescue EOFError
      retry
    end

    # Services
    def services
      get("services", nil => :json)
    end

    def create_service(manifest)
      post(manifest, "services", :json => :json)
    end

    def service(name)
      get("services", name, nil => :json)
    end

    def delete_service(name)
      delete("services", name, nil => :json)
      true
    end

    private

    def handle_response(response, accept)
      json = accept == :json

      case response
      when Net::HTTPSuccess, Net::HTTPRedirection
        if accept == :headers
          return sane_headers(response)
        end

        if json
          if response.code == 204
            raise "Expected JSON response, got 204 No Content"
          end

          parse_json(response.body)
        else
          response.body
        end

      when Net::HTTPBadRequest, Net::HTTPForbidden
        info = parse_json(response.body)
        raise CFoundry::Denied.new(403, info[:description])

      when Net::HTTPNotFound
        raise CFoundry::NotFound

      when Net::HTTPServerError
        begin
          raise_error(parse_json(response.body))
        rescue MultiJson::DecodeError
          raise CFoundry::BadResponse.new(response.code, response.body)
        end

      else
        raise CFoundry::BadResponse.new(response.code, response.body)
      end
    end

    def raise_error(info)
      case info[:code]
      when 402
        raise CFoundry::UploadFailed.new(info[:description])
      else
        raise CFoundry::APIError.new(info[:code], info[:description])
      end
    end
  end
end
