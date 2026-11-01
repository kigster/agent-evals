# frozen_string_literal: true

require "net/http"

module LLM
  module Evals
    module Providers
      # One GET of a provider's model list, parsed. Every failure becomes an
      # {Error} that names the URL, so an offline run says so instead of
      # printing a socket error from inside a provider.
      module Catalog
        module_function

        # @param url [String]
        # @param headers [Hash{String => String}]
        # @return [Hash] the parsed JSON body
        # @raise [Error] when the list cannot be read
        def fetch(url, headers = {})
          uri = URI(url)
          response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 20) do |http|
            http.request(Net::HTTP::Get.new(uri, headers))
          end
          raise Error, "could not list models at #{url}: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

          JSON.parse(response.body)
        rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, JSON::ParserError, KeyError => e
          raise Error, "could not list models at #{url}: #{e.message}"
        end
      end
    end
  end
end
