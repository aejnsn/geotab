# Add support for simple query methods such as where, find, all, and first.
# Where clauses are chainable and are simply appended to the search param.
#
# Ex:
#   Geotab::Device.with_connection(conn).
#     where({"serialNumber" => "G7B020D3E1A4"}).
#     where({"name" => "07 BMW 335i"}).
#     all
#
# Ex:
#   Geotab::Defect.find("b2775")
module Geotab
  module Concerns
    module Findable
      module ClassMethods
        include Geotab::Concerns::Conditionable
        include Geotab::Concerns::Connectable

        GROUP_ENTITIES = %w[ Defect ].freeze

        # Format of conditions should match that of geotab's sdk, as the
        # conditions are passed pretty much as is to the API.
        def where(params={})
          conditions.merge!(params)

          self
        end

        # If the id of the resource is known, query it using a simple where
        # clause. Note that most geotab resources do not allow other conditions
        # if the id is specified.
        def find(id)
          where({'id' => "#{id}"}).first
        end

        # Each query should include this method at the end to perform the
        # actual call to the API.
        def all
          params = {
            method: "Get",
            params: { typeName: geotab_reference_name,
                      credentials: connection.credentials,
                      search: conditions }
          }

          response = make_request("https://#{connection.path}/apiv1/", params)

          attributes = response.result
          result = []

          push_results(result, attributes)

          result
        ensure
          reset
        end

        def get_feed(from_version)
          params = {
            method: "GetFeed",
            params: { typeName: geotab_reference_name,
                      credentials: connection.credentials,
                      search: conditions,
                      fromVersion: from_version }
          }

          response = make_request("https://#{connection.path}/apiv1/", params)
          result = { results: [] }

          attributes = response.result.data
          result[:to_version] = response.result.toVersion
          push_results(result[:results], attributes)

          result
        ensure
          reset
        end

        def make_request(path, params)
          res = Net::HTTP.post(URI(path), params.to_json, "Content-Type" => "application/json", "Accept" => "application/json")
          body = convert_to_ostruct_recursive(JSON.parse(res.body))

          if body.error
            if body.error.errors.first.message.start_with?("Incorrect MyGeotab login credentials")
              raise IncorrectCredentialsError, body.error.errors.first.message
            else
              raise ApiError, body.error.errors.first.message
            end
          end

          body
        end

        def first
          all[0]
        end

        def push_results(results, attributes)
          if attributes && attributes.any?
            attributes.each do |result|
              results.push(new(result, connection))
            end
          end
        end

        # This value is passed to geotab as the typeName param. This method
        # substitutes "Group" for the typeName when the type of object is a
        # Group object.
        #
        # See: https://my.geotab.com/sdk/api/apiReference.html (Look up Group in the Search box)
        # See: https://helpdesk.geotab.com/hc/en-us/community/posts/115019270503-Trouble-Making-Certain-API-Calls
        # See: https://helpdesk.geotab.com/hc/en-us/community/posts/115009238926-defects
        #
        # It also translates class names that don't exactly match Geotab
        # reference names when their naming doesn't make sense (Data/Datum).
        #
        # Returns a String.
        def geotab_reference_name
          class_name = self.to_s.split("::").last
          if GROUP_ENTITIES.include?(class_name)
            "Group"
          else
            class_name.gsub("Datum", "Data")
          end
        end

        # Should run this after each query to avoid stale data
        def reset
          # Conditions are now stale, so clear them
          clear_conditions

          # Connection is also stale
          clear_connection
        end

        def convert_to_ostruct_recursive(obj)
          result = obj
          if result.is_a? Hash
            result = with_sym_keys(result.dup)
            result.each  do |key, val|
              result[key] = convert_to_ostruct_recursive(val)
            end
            result = OpenStruct.new result
          elsif result.is_a? Array
             result = result.map { |r| convert_to_ostruct_recursive(r) }
          end
          return result
        end

        def with_sym_keys(hash)
          hash.inject({}) { |memo, (k,v)| memo[k.to_sym] = v; memo }
        end
      end

      def self.included(base)
        base.extend(ClassMethods)
      end

    end
  end
end
