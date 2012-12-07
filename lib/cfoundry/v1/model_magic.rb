require "cfoundry/validator"

module CFoundry::V1
  module BaseClientMethods
  end

  module ClientMethods
  end

  module ModelMagic
    attr_accessor :guid_name

    def defaults
      @defaults ||= {}
    end

    def attributes
      @attributes ||= {}
    end

    def read_locations
      @read_locations ||= {}
    end

    def write_locations
      @write_locations ||= {}
    end

    def define_client_methods(klass = self)
      singular = klass.object_name
      plural = :"#{singular}s"

      base_singular = klass.base_object_name
      base_plural = :"#{base_singular}s"

      BaseClientMethods.module_eval do
        define_method(base_singular) do |guid|
          get(base_plural, guid, :accept => :json)
        end

        define_method(:"create_#{base_singular}") do |payload|
          post(payload, base_plural, :content => :json, :accept => :json)
        end

        define_method(:"delete_#{base_singular}") do |guid|
          delete(base_plural, guid)
          true
        end

        define_method(:"update_#{base_singular}") do |guid, payload|
          put(payload, base_plural, guid, :content => :json)
        end

        define_method(base_plural) do |*args|
          get(base_plural, :accept => :json)
        end
      end

      ClientMethods.module_eval do
        define_method(singular) do |*args|
          guid, _ = args
          klass.new(guid, self)
        end

        define_method(plural) do |*args|
          options, _ = args
          options ||= {}

          @base.send(base_plural).collect do |json|
            klass.new(json[klass.guid_name], self, json)
          end
        end
      end
    end

    def attribute(name, type, opts = {})
      attributes[name] = opts

      default = opts[:default]
      is_guid = opts[:guid]
      read_only = opts[:read_only]
      write_only = opts[:write_only]

      if has_default = opts.key?(:default)
        defaults[name] = default
      end

      read_locations[name] = Array(opts[:read] || opts[:at] || name)
      write_locations[name] = Array(opts[:write] || opts[:at] || name)

      if is_guid
        self.guid_name = name
        singular = object_name

        ClientMethods.module_eval do
          define_method(:"#{singular}_by_#{name}") do |guid|
            obj = send(singular, guid)
            obj if obj.exists?
          end
        end
      end

      unless write_only
        define_method(name) do
          return @cache[name] if @cache.key?(name)
          return @guid if @guid && is_guid

          read = read_manifest
          @cache[name] = read.key?(name) ? read[name] : default
        end
      end

      return if read_only

      define_method(:"#{name}=") do |val|
        unless has_default && val == default
          CFoundry::Validator.validate_type(val, type)
        end

        @guid = val if is_guid

        @cache[name] = val

        @manifest ||= {}

        old = read_manifest[name] if @manifest
        @changes[name] = [old, val] if old != val

        put(val, @manifest, self.class.write_locations[name])
      end
    end
  end
end
