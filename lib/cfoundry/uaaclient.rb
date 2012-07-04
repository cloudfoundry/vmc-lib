module CFoundry
  class UAAClient < BaseClient
    attr_accessor :target

    def initialize(target = "https://uaa.cloudfoundry.com")
      @target = target
    end

    def prompts
      get("prompts", nil => :json)
    end
  end
end
