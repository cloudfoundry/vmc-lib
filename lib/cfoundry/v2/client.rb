require "base64"

require "cfoundry/v2/base"

require "cfoundry/v2/app"
require "cfoundry/v2/framework"
require "cfoundry/v2/organization"
require "cfoundry/v2/runtime"
require "cfoundry/v2/service"
require "cfoundry/v2/service_binding"
require "cfoundry/v2/service_instance"
require "cfoundry/v2/service_plan"
require "cfoundry/v2/space"
require "cfoundry/v2/user"

module CFoundry::V2
  # The primary API entrypoint. Wraps a BaseClient to provide nicer return
  # values. Initialize with the target and, optionally, an auth token. These
  # are the only two internal states.
  class Client
    # Internal BaseClient instance. Normally won't be touching this.
    attr_reader :base

    # [Organization] Currently targeted organization.
    attr_accessor :current_organization

    # [Space] Currently targeted space.
    attr_accessor :current_space


    # Create a new Client for interfacing with the given target.
    #
    # A token may also be provided to skip the login step.
    def initialize(target = "http://api.cloudfoundry.com", token = nil)
      @base = Base.new(target, token)
    end

    # The current target URL of the client.
    def target
      @base.target
    end

    # Current proxy user. Usually nil.
    def proxy
      @base.proxy
    end

    # Set the proxy user for the client. Must be authorized as an
    # administrator for this to have any effect.
    def proxy=(email)
      @base.proxy = email
    end

    # Is the client tracing API requests?
    def trace
      @base.trace
    end

    # Set the tracing flag; if true, API requests and responses will be
    # printed out.
    def trace=(bool)
      @base.trace = bool
    end

    # The currently authenticated user.
    def current_user
      if guid = token_data[:user_id]
        user = user(guid)
        user.emails = [{ :value => token_data[:email] }]
        user
      end
    end

    # Cloud metadata
    def info
      @base.info
    end

    # Login prompts
    def login_prompts
      if @base.uaa
        @base.uaa.prompts
      else
        { :username => ["text", "Email"],
          :password => ["password", "Password"]
        }
      end
    end

    # Authenticate with the target. Sets the client token.
    #
    # Credentials is a hash, typically containing :username and :password
    # keys.
    #
    # The values in the hash should mirror the prompts given by
    # `login_prompts`.
    def login(credentials)
      @current_organization = nil
      @current_space = nil

      @base.token =
        if @base.uaa
          @base.uaa.authorize(credentials)
        else
          @base.create_token(
            { :password => credentials[:password] },
            credentials[:username])[:token]
        end
    end

    # Clear client token. No requests are made for this.
    def logout
      @base.token = nil
    end

    # Is an authentication token set on the client?
    def logged_in?
      !!@base.token
    end


    [ :app, :organization, :space, :user, :runtime, :framework,
      :service, :service_plan, :service_binding, :service_instance
    ].each do |singular|
      plural = :"#{singular}s"

      classname = singular.to_s.capitalize.gsub(/(.)_(.)/) do
        $1 + $2.upcase
      end

      klass = CFoundry::V2.const_get(classname)

      has_space = klass.method_defined? :space
      has_name = klass.method_defined? :name

      define_method(singular) do |*args|
        guid, _ = args
        klass.new(guid, self)
      end

      define_method(plural) do |*args|
        depth, query = args
        depth ||= 1

        if has_space && current_space
          query ||= {}
          query[:space_guid] ||= current_space.guid
        end

        @base.send(plural, depth, query)[:resources].collect do |json|
          send(:"make_#{singular}", json)
        end
      end

      if has_name
        define_method(:"#{singular}_by_name") do |name|
          if has_space && current_space
            current_space.send(plural, 1, :name => name).first
          else
            send(plural, 1, :name => name).first
          end
        end
      end

      define_method(:"#{singular}_from") do |path, *args|
        send(
          :"make_#{singular}",
          @base.request_path(
            :get,
            path,
            nil => :json,
            :params => @base.params_from(args)))
      end

      define_method(:"#{plural}_from") do |path, *args|
        @base.request_path(
            :get,
            path,
            nil => :json,
            :params => @base.params_from(args))[:resources].collect do |json|
          send(:"make_#{singular}", json)
        end
      end

      define_method(:"make_#{singular}") do |json|
        klass.new(
          json[:metadata][:guid],
          self,
          json)
      end
    end

    private

    # grab the metadata from a token that looks like:
    #
    # bearer (base64 ...)
    def token_data
      tok = Base64.decode64(@base.token.sub(/^bearer\s+/, ""))
      tok.sub!(/\{.+?\}/, "") # clear algo
      JSON.parse(tok[/\{.+?\}/], :symbolize_names => true)

    # normally i don't catch'em all, but can't expect all tokens to be the
    # proper format, so just silently fail as this is not critical
    rescue
      {}
    end
  end
end