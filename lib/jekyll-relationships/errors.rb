# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships

# Base exception for all relationship-processing failures.
#
# Rescue this if you want to treat plugin errors as one family.
class Error < StandardError
end

# Raised when the site configuration defines impossible or ambiguous rules.
#
# These errors should normally be fixed in `_config.yml`.
class ConfigurationError < Error
end

# Raised when relationship data cannot be resolved safely.
#
# These errors generally point to invalid references or recursive resolver
# behaviour in site content.
class ResolutionError < Error
end

end

end
end
