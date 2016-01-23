$:.unshift '.'

# Set ENV['NLS_LANG'] for OCI8
ENV['NLS_LANG']='AMERICAN_AMERICA.UTF8'

# setup test suite
require 'minitest/autorun'

# external libs
require 'active_support/all'
require 'date'
require 'net/http'
require 'net/https'
require 'net/http/post/multipart'
require 'nokogiri'
require 'sequel'
require 'tzinfo'
require 'yaml'
require 'gmail'
require 'm'
require 'pp'

# local libs
require 'lib/config'
require 'lib/common'
require 'lib/hash'
require 'lib/oracle'
require 'lib/http_helpers'
require 'lib/assertion_helpers'
require 'lib/inspectify_helpers'
require 'lib/panda_helpers'
require 'lib/turtle_helpers'
require 'lib/snake_helpers'
require 'lib/dragon_helpers'
require 'lib/image_helpers'
require 'lib/gmail_helpers'
require 'lib/facebook_helpers'
require 'lib/em_helpers'
require 'lib/sso_helpers'
require 'lib/turtle_user'
require 'lib/sso_user'
require 'lib/pro_helpers'

# Allows True & False respond to Boolean
module Boolean
end
class TrueClass
  include Boolean
end
class FalseClass
  include Boolean
end

# A really dumb hack so that we can send a request with a body multiple times without erroring.
# Taken from https://github.com/jpatokal/mediawiki-gateway/issues/25
module Net
  class HTTPGenericRequest
    def set_body_internal(str)   #:nodoc: internal use only
      raise ArgumentError, "both of body argument and HTTPRequest#body set" if (str and @body and str != @body) or (str and @body_stream)
      self.body = str if str
    end
  end
end

# All tests should inherit from this class
class APITest < MiniTest::Test
  # Add all Helpers to this list of includes
  include AssertionHelpers, PandaHelpers, FacebookHelpers, GmailHelpers, HttpHelpers, DragonHelpers, PromoHelpers,
          ImageHelpers, InspectifyHelpers, TurtleHelpers, SnakeHelpers, SSOHelpers, EmailHelpers
end

MiniTest.after_run do
  Oracle.delete_all_test_ugc
end unless ENV['IRB'] == 'true'
