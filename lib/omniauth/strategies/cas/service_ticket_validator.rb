require 'net/http'
require 'net/https'
require 'nokogiri'

module OmniAuth
  module Strategies
    class CAS
      class ServiceTicketValidator

        VALIDATION_REQUEST_HEADERS = { 'Accept' => '*/*' }

        # Build a validator from a +configuration+, a
        # +return_to+ URL, and a +ticket+.
        #
        # @param [Hash] options the OmniAuth Strategy options
        # @param [String] return_to_url the URL of this CAS client service
        # @param [String] ticket the service ticket to validate
        def initialize(strategy, options, return_to_url, ticket)
          @options = options
          @uri = URI.parse(strategy.service_validate_url(return_to_url, ticket))
        end

        # Request validation of the ticket from the CAS server's
        # serviceValidate (CAS 2.0) function.
        #
        # Swallows all XML parsing errors (and returns +nil+ in those cases).
        #
        # @return [Hash, nil] a user information hash if the response is valid; +nil+ otherwise.
        #
        # @raise any connection errors encountered.
        def user_info
          parse_user_info( find_authentication_success( get_service_response_body ) )
        end

      private
       
        # extra option for cas version
        def cas_1?
          @options.cas_version && @options.cas_version == '1.0'
        end


        # turns an `<cas:authenticationSuccess>` node into a Hash;
        # returns nil if given nil
       def parse_user_info_with_cas_1(result_array)
          if cas_1?
            result = {}
            return result if result_array.nil?
            result['name'] = result_array[1]
            result['extra_info'] = result_array[2..-1]
            result
          else
            parse_user_info_without_cas_1(result_array)
          end
        end
        alias_method_chain :parse_user_info, :cas_1

        def parse_user_info(node)
          return nil if node.nil?

          {}.tap do |hash|
            node.children.each do |e|
              node_name = e.name.sub(/^cas:/, '')
              unless e.kind_of?(Nokogiri::XML::Text) ||
                     node_name == 'proxies'
                # There are no child elements
                if e.element_children.count == 0
                  hash[node_name] = e.content
                elsif e.element_children.count
                  # JASIG style extra attributes
                  if node_name == 'attributes'
                    hash.merge! parse_user_info e
                  else
                    hash[node_name] = [] if hash[node_name].nil?
                    hash[node_name].push parse_user_info e
                  end
                end
              end
            end
          end
        end

        # finds an `<cas:authenticationSuccess>` node in
        # a `<cas:serviceResponse>` body if present; returns nil
        # if the passed body is nil or if there is no such node.
        
        def find_authentication_success_with_cas_1(body)
          if cas_1?
            return nil if body.nil? || body == ''
            result = body.split("\n")
            return nil if result[0] == 'no'
            result
          else
            find_authentication_success_without_cas_1(body)
          end
        end
        alias_method_chain :find_authentication_success, :cas_1

        def find_authentication_success(body)
          return nil if body.nil? || body == ''
          begin
            doc = Nokogiri::XML(body)
            begin
              doc.xpath('/cas:serviceResponse/cas:authenticationSuccess')
            rescue Nokogiri::XML::XPath::SyntaxError
              doc.xpath('/serviceResponse/authenticationSuccess')
            end
          rescue Nokogiri::XML::XPath::SyntaxError
            nil
          end
        end

        # retrieves the `<cas:serviceResponse>` XML from the CAS server
        def get_service_response_body
          result = ''
          http = Net::HTTP.new(@uri.host, @uri.port)
          http.use_ssl = @uri.port == 443 || @uri.instance_of?(URI::HTTPS)
          if http.use_ssl?
            http.verify_mode = OpenSSL::SSL::VERIFY_NONE if @options.disable_ssl_verification?
            http.ca_path = @options.ca_path
          end
          http.start do |c|
            response = c.get "#{@uri.path}?#{@uri.query}", VALIDATION_REQUEST_HEADERS.dup
            result = response.body
          end
          result
        end

      end
    end
  end
end
