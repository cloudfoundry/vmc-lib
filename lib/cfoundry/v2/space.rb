require "cfoundry/v2/model"

module CFoundry::V2
  class AppSpace < Model
    attribute :name
    to_one    :organization
    to_many   :developers
    to_many   :managers
    to_many   :auditors
    to_many   :apps
    to_many   :domains
  end
end
