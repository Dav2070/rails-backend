class ApplicationController < ActionController::API
   
   def check_authorization(api_key, signature)
      dev = Dev.find_by(api_key: api_key)
      
      if !dev
         false
      else
         if api_key == dev.api_key
            
            new_sig = Base64.strict_encode64(OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), dev.secret_key, dev.uuid))
            
            if new_sig == signature
               true
            else
               false
            end
         else
            false
         end
      end
	end
	
	def validate_url(url)
      /\A#{URI::regexp}\z/.match?(url)
   end

   def get_file_size(file)
      size = 0

      if file.class == StringIO
         size = file.size
      else
         size = File.size(file)
      end

      return size
   end
	
	def get_file_size_of_table_object(obj_id)
      obj = TableObject.find_by_id(obj_id)

		if !obj
			return
		end
		
      obj.properties.each do |prop| # Get the size property of the table_object
         if prop.name == "size"
            return prop.value.to_i
         end
      end

      # If size property was not saved, get file size directly from Azure
      Azure.config.storage_account_name = ENV["AZURE_STORAGE_ACCOUNT"]
      Azure.config.storage_access_key = ENV["AZURE_STORAGE_ACCESS_KEY"]
      client = Azure::Blob::BlobService.new

      begin
         # Check if the object is a file
         blob = client.get_blob(ENV['AZURE_FILES_CONTAINER_NAME'], "#{obj.table.app_id}/#{obj.id}")
         return blob[0].properties[:content_length].to_i # The size of the file in bytes
      rescue Exception => e
         puts e
      end

      return 0
   end

	def get_total_storage(plan, confirmed)
		storage_unconfirmed = 1000000000 	# 1 GB
      storage_on_free_plan = 5000000000 	# 5 GB
		storage_on_plus_plan = 50000000000 	# 50 GB

		if !confirmed
			return storage_unconfirmed
      elsif plan == 1 # User is on Plus plan
			return storage_on_plus_plan
		else
			return storage_on_free_plan
		end
   end

   def save_email_to_stripe_customer(user)
      if user.stripe_customer_id
         begin
            customer = Stripe::Customer.retrieve(user.stripe_customer_id)
            if customer
               customer.email = user.email
               customer.save
            end
         rescue => e
            
         end
      end
	end
	
	def generate_table_object_etag(object)
		# id,table_id,user_id,visibility,uuid,file,property1Name:property1Value,property2Name:property2Value,...
		etag_string = "#{object.id},#{object.table_id},#{object.user_id},#{object.visibility},#{object.uuid},#{object.file}"

		object.properties.each do |prop|
			etag_string += ",#{prop.name}:#{prop.value}"
		end

		return Digest::MD5.hexdigest(etag_string)
	end

	def update_used_storage(user_id, app_id, storage_change)
		update_used_storage_of_user(user_id, storage_change)
		update_used_storage_of_app(user_id, app_id, storage_change)
	end

	def update_used_storage_of_user(user_id, storage_change)
		user = User.find_by_id(user_id)

		if user
			user.used_storage = user.used_storage += storage_change
			user.save
		end
	end

	def update_used_storage_of_app(user_id, app_id, storage_change)
		users_app = UsersApp.find_by(user_id: user_id, app_id: app_id)

		if users_app
			users_app.used_storage = users_app.used_storage += storage_change
			users_app.save
		end
   end
end
