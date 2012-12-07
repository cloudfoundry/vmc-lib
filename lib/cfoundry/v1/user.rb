require "cfoundry/v1/model"

module CFoundry::V1
  class User < Model
    define_client_methods

    attribute :email,    :string, :guid => true
    attribute :password, :string, :write_only => true
    attribute :admin,    :boolean

    alias_method :admin?, :admin

    def change_password!(new, old)
      if @client.base.uaa
        @client.base.uaa.change_password(guid, new, old)
      else
        self.password = new
        update!
      end
    end
  end
end
