require "tmpdir"
require "multi_json"

require "cfoundry/zip"
require "cfoundry/upload_helpers"
require "cfoundry/chatty_hash"

require "cfoundry/v2/model"

module CFoundry::V2
  # Class for representing a user's application on a given target (via
  # Client).
  #
  # Does not guarantee that the app exists; used for both app creation and
  # retrieval, as the attributes are all lazily retrieved. Setting attributes
  # does not perform any requests; use #update! to commit your changes.
  class App < Model
    include CFoundry::UploadHelpers

    attribute :name,             :string
    attribute :production,       :boolean, :default => false
    to_one    :space
    to_one    :runtime
    to_one    :framework
    attribute :environment_json, :hash,    :default => {}
    attribute :memory,           :integer, :default => 256
    attribute :instances,        :integer, :default => 1
    attribute :file_descriptors, :integer, :default => 256
    attribute :disk_quota,       :integer, :default => 256
    attribute :state,            :integer, :default => "STOPPED"
    attribute :command,          :string,  :default => nil
    attribute :console,          :boolean, :default => false
    to_many   :service_bindings
    to_many   :routes

    scoped_to_space

    alias :total_instances :instances
    alias :total_instances= :instances=

    private :environment_json

    def instances
      @client.base.instances(@guid).collect do |i, m|
        Instance.new(self, i.to_s, @client, m)
      end
    end

    def crashes
      @client.base.crashes(@guid).collect do |m|
        Instance.new(self, m[:instance], @client, m)
      end
    end

    def stats
      stats = {}

      @client.base.stats(@guid).each do |idx, info|
        stats[idx.to_s] = info
      end

      stats
    end

    def services
      service_bindings.collect(&:service_instance)
    end

    def env
      @env ||= CFoundry::ChattyHash.new(
        method(:env=),
        environment_json)
    end

    def env=(x)
      self.environment_json = x.to_hash
    end

    def debug_mode # TODO v2
      nil
    end

    def uris
      routes.collect do |r|
        "#{r.host}.#{r.domain.name}"
      end
    end
    alias :urls :uris

    def uris=(uris)
      raise "App#uris= is invalid against V2 APIs. Use add/remove_route."
    end
    alias :urls= :uris=

    def create_routes(*uris)
      uris.each do |uri|
        host, domain_name = uri.split(".", 2)

        domain =
          @client.current_space.domains.find { |d|
            d.name == domain_name
          }

        raise "Invalid domain '#{domain_name}'" unless domain

        route = @client.routes.find { |r|
          r.host == host && r.domain == domain
        }

        unless route
          route = @client.route
          route.host = host
          route.domain = domain
          route.organization = @client.current_organization
          route.create!
        end

        add_route(route)
      end
    end
    alias :create_route :create_routes

    def uri
      if route = routes.first
        "#{route.host}.#{route.domain.name}"
      end
    end
    alias :url :uri

    def uri=(x)
      self.uris = [x]
    end
    alias :url= :uri=

    # Stop the application.
    def stop!
      update! :state => "STOPPED"
    end

    # Start the application.
    def start!
      update! :state => "STARTED"
    end

    # Restart the application.
    def restart!
      stop!
      start!
    end

    # Determine application health.
    #
    # If all instances are running, returns "RUNNING". If only some are
    # started, returns the precentage of them that are healthy.
    #
    # Otherwise, returns application's status.
    def health
      state
    end

    # Check that all application instances are running.
    def healthy?
      # invalidate cache so the check is fresh
      @manifest = nil

      case health
      when "RUNNING", "STARTED"
        true
      end
    end
    alias_method :running?, :healthy?

    # Is the application stopped?
    def stopped?
      state == "STOPPED"
    end

    # Is the application started?
    #
    # Note that this does not imply that all instances are running. See
    # #healthy?
    def started?
      state == "STARTED"
    end

    # Bind services to application.
    def bind(*instances)
      instances.each do |i|
        binding = @client.service_binding
        binding.app = self
        binding.service_instance = i
        binding.create!
      end

      self
    end

    # Unbind services from application.
    def unbind(*instances)
      service_bindings.each do |b|
        if instances.include? b.service_instance
          b.delete!
        end
      end

      self
    end

    def binds?(instance)
      service_bindings.any? { |b|
        b.service_instance == instance
      }
    end

    # Upload application's code to target. Do this after #create! and before
    # #start!
    #
    # [path]
    #   A path pointing to either a directory, or a .jar, .war, or .zip
    #   file.
    #
    #   If a .vmcignore file is detected under the given path, it will be used
    #   to exclude paths from the payload, similar to a .gitignore.
    #
    # [check_resources]
    #   If set to `false`, the entire payload will be uploaded
    #   without checking the resource cache.
    #
    #   Only do this if you know what you're doing.
    def upload(path, check_resources = true)
      unless File.exist? path
        raise "invalid application path '#{path}'"
      end

      zipfile = "#{Dir.tmpdir}/#{@guid}.zip"
      tmpdir = "#{Dir.tmpdir}/.vmc_#{@guid}_files"

      FileUtils.rm_f(zipfile)
      FileUtils.rm_rf(tmpdir)

      prepare_package(path, tmpdir)

      resources = determine_resources(tmpdir) if check_resources

      packed = CFoundry::Zip.pack(tmpdir, zipfile)

      @client.base.upload_app(@guid, packed && zipfile, resources || [])
    ensure
      FileUtils.rm_f(zipfile) if zipfile
      FileUtils.rm_rf(tmpdir) if tmpdir
    end

    def files(*path)
      Instance.new(self, "0", @client).files(*path)
    end

    def file(*path)
      Instance.new(self, "0", @client).file(*path)
    end

    class Instance
      attr_reader :app, :id

      def initialize(app, id, client, manifest = {})
        @app = app
        @id = id
        @client = client
        @manifest = manifest
      end

      def inspect
        "#<App::Instance '#{@app.name}' \##@id>"
      end

      def state
        @manifest[:state]
      end
      alias_method :status, :state

      def since
        if since = @manifest[:since]
          Time.at(@manifest[:since])
        end
      end

      def debugger
        return unless @manifest[:debug_ip] and @manifest[:debug_port]

        { :ip => @manifest[:debug_ip],
          :port => @manifest[:debug_port]
        }
      end

      def console
        return unless @manifest[:console_ip] and @manifest[:console_port]

        { :ip => @manifest[:console_ip],
          :port => @manifest[:console_port]
        }
      end

      def healthy?
        case state
        when "STARTING", "RUNNING"
          true
        when "DOWN", "FLAPPING"
          false
        end
      end

      def files(*path)
        @client.base.files(@app.guid, @id, *path).split("\n").collect do |entry|
          path + [entry.split(/\s+/, 2)[0]]
        end
      end

      def file(*path)
        @client.base.files(@app.guid, @id, *path)
      end
    end

    private

    # Minimum size for an application payload to bother checking resources.
    RESOURCE_CHECK_LIMIT = 64 * 1024

    def determine_resources(path)
      fingerprints, total_size = make_fingerprints(path)

      return if total_size <= RESOURCE_CHECK_LIMIT

      resources = @client.base.resource_match(fingerprints)

      resources.each do |resource|
        FileUtils.rm_f resource[:fn]
        resource[:fn].sub!("#{path}/", "")
      end

      resources
    end
  end
end