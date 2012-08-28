module CFoundry::V1
  # Class for representing a user on a given target (via Client).
  #
  # Does not guarantee that the user exists; used for both user creation and
  # retrieval, as the attributes are all lazily retrieved. Setting attributes
  # does not perform any requests; use #update! to commit your changes.
  class User
    # User email.
    attr_reader :email


    # Create a User object.
    #
    # You'll usually call Client#user instead
    def initialize(email, client, manifest = nil)
      @email = email
      @client = client
      @manifest = manifest
    end

    # Show string representing the user.
    def inspect
      "#<User '#@email'>"
    end

    # Basic equality test by email.
    def eql?(other)
      other.is_a?(self.class) && other.email == @email
    end
    alias :== :eql?

    # Delete the user from the target.
    def delete!
      @client.base.delete_user(@email)
    end

    # Create the user on the target.
    #
    # Call this after setting the various attributes.
    def create!
      @client.base.create_user(@manifest.merge(:email => @email))
    end

    # Update user attributes.
    def update!(what = {})
      @client.base.update_user(@email, manifest.merge(what))
      @manifest = nil
    end

    # Check if the user exists on the target.
    def exists?
      @client.base.user(@email)
      true
    rescue CFoundry::Denied
      false
    end

    # Check if the user is an administrator.
    def admin?
      manifest[:admin]
    end

    # Set the user's password.
    #
    # Call #update! after using this.
    def password=(str)
      manifest[:password] = str
    end

    def change_password!(new)
      self.password = new
      update!
    end

    private

    def manifest
      @manifest ||= @client.base.user(@email)
    end
  end
end
