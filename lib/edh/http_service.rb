require 'faraday'
require 'edh/http_service/multipart_request'
require 'edh/http_service/response'

module EDH
  module HTTPService
    class << self
      # A customized stack of Faraday middleware that will be used to make each request.
      attr_accessor :faraday_middleware
      attr_accessor :http_options
    end

    @http_options ||= {}

    # EDH's default middleware stack.
    # We encode requests in a Passport-compatible multipart request,
    # and use whichever adapter has been configured for this application.
    DEFAULT_MIDDLEWARE = Proc.new do |builder|
      builder.use EDH::HTTPService::MultipartRequest
      builder.request :url_encoded
      builder.adapter Faraday.default_adapter
    end

    # The address of the appropriate Passport server.
    #
    # @param options various flags to indicate which server to use.
    # @option options :rest_api use the old REST API instead of the Graph API
    # @option options :use_ssl force https, even if not needed
    #
    # @return a complete server address with protocol
    def self.server(options = {})
      if options[:server]
        options[:server]
      else
        server = Passport::REST_SERVER
        "#{options[:use_ssl] ? "https" : "http"}://#{server}"
      end
    end

    # Makes a request directly to Passport.
    # @note You'll rarely need to call this method directly.
    #
    # @see EDH::Passport::API#api
    # @see EDH::Passport::RestAPIMethods#rest_call
    #
    # @param path the server path for this request
    # @param args (see EDH::Passport::API#api)
    # @param verb the HTTP method to use.
    #             If not get or post, this will be turned into a POST request with the appropriate :method
    #             specified in the arguments.
    # @param options (see EDH::Passport::API#api)
    #
    # @raise an appropriate connection error if unable to make the request to Passport
    #
    # @return [EDH::HTTPService::Response] a response object representing the results from Passport
    def self.make_request(path, args, verb, options = {})
      # if the verb isn't get or post, send it as a post argument
      args.merge!({:method => verb}) && verb = "post" if verb != "get" && verb != "post"

      # turn all the keys to strings (Faraday has issues with symbols under 1.8.7)
      params = args.inject({}) {|hash, kv| hash[kv.first.to_s] = kv.last; hash}

      # figure out our options for this request
      request_options = {:params => (verb == "get" ? params : {})}.merge(http_options || {}).merge(process_options(options))
      if request_options[:use_ssl]
        ssl = (request_options[:ssl] ||= {})
        ssl[:verify] = true unless ssl.has_key?(:verify)
      end

      # set up our Faraday connection
      # we have to manually assign params to the URL or the
      conn = Faraday.new(server(request_options), request_options, &(faraday_middleware || DEFAULT_MIDDLEWARE))

      response = conn.send(verb, path, (verb == "post" ? params : {}))

      # Log URL information
      EDH::Utils.debug "#{verb.upcase}: #{path} params: #{params.inspect}"
      EDH::HTTPService::Response.new(response.status.to_i, response.body, response.headers)
    end

    # Encodes a given hash into a query string.
    # This is used mainly by the Batch API nowadays, since Faraday handles this for regular cases.
    #
    # @param params_hash a hash of values to CGI-encode and appropriately join
    #
    # @example
    #   EDH.http_service.encode_params({:a => 2, :b => "My String"})
    #   => "a=2&b=My+String"
    #
    # @return the appropriately-encoded string
    def self.encode_params(param_hash)
      ((param_hash || {}).sort_by{|k, v| k.to_s}.collect do |key_and_value|
        key_and_value[1] = MultiJson.dump(key_and_value[1]) unless key_and_value[1].is_a? String
        "#{key_and_value[0].to_s}=#{CGI.escape key_and_value[1]}"
      end).join("&")
    end

    private

    def self.process_options(options)
      if typhoeus_options = options.delete(:typhoeus_options)
        EDH::Utils.deprecate("typhoeus_options should now be included directly in the http_options hash.  Support for this key will be removed in a future version.")
        options = options.merge(typhoeus_options)
      end

      if ca_file = options.delete(:ca_file)
        EDH::Utils.deprecate("http_options[:ca_file] should now be passed inside (http_options[:ssl] = {}) -- that is, http_options[:ssl][:ca_file].  Support for this key will be removed in a future version.")
        (options[:ssl] ||= {})[:ca_file] = ca_file
      end

      if ca_path = options.delete(:ca_path)
        EDH::Utils.deprecate("http_options[:ca_path] should now be passed inside (http_options[:ssl] = {}) -- that is, http_options[:ssl][:ca_path].  Support for this key will be removed in a future version.")
        (options[:ssl] ||= {})[:ca_path] = ca_path
      end

      if verify_mode = options.delete(:verify_mode)
        EDH::Utils.deprecate("http_options[:verify_mode] should now be passed inside (http_options[:ssl] = {}) -- that is, http_options[:ssl][:verify_mode].  Support for this key will be removed in a future version.")
        (options[:ssl] ||= {})[:verify_mode] = verify_mode
      end

      options
    end
  end

  # @private
  module TyphoeusService
    def self.deprecated_interface
      # support old-style interface with a warning
      EDH::Utils.deprecate("the TyphoeusService module is deprecated; to use Typhoeus, set Faraday.default_adapter = :typhoeus.  Enabling Typhoeus for all Faraday connections.")
      Faraday.default_adapter = :typhoeus
    end
  end

  # @private
  module NetHTTPService
    def self.deprecated_interface
      # support old-style interface with a warning
      EDH::Utils.deprecate("the NetHTTPService module is deprecated; to use Net::HTTP, set Faraday.default_adapter = :net_http.  Enabling Net::HTTP for all Faraday connections.")
      Faraday.default_adapter = :net_http
    end
  end
end