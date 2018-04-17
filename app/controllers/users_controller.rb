class UsersController < ApplicationController
   require 'jwt'
   min_username_length = 2
   max_username_length = 25
   min_password_length = 7
   max_password_length = 25
   
   define_method :signup do
      email = params[:email]
      password = params[:password]
      username = params[:username]
      
      auth = request.headers['HTTP_AUTHORIZATION'].to_s.length < 2 ? params["auth"].to_s.split(' ').last : request.headers['HTTP_AUTHORIZATION'].to_s.split(' ').last
      if auth
         api_key = auth.split(",")[0]
         sig = auth.split(",")[1]
      end
      
      errors = Array.new
      @result = Hash.new
      ok = false
      
      if !email || email.length < 1
         errors.push(Array.new([2106, "Missing field: email"]))
         status = 400
      end
      
      if !password || password.length < 1
         errors.push(Array.new([2107, "Missing field: password"]))
         status = 400
      end
      
      if !username || username.length < 1
         errors.push(Array.new([2105, "Missing field: username"]))
         status = 400
      end
      
      if !auth || auth.length < 1
         errors.push(Array.new([2101, "Missing field: auth"]))
         status = 401
      end
      
      if errors.length == 0
         dev = Dev.find_by(api_key: api_key)
         
         if !dev     # Check if the dev exists
            errors.push(Array.new([2802, "Resource does not exist: Dev"]))
            status = 400
         else
            if !check_authorization(api_key, sig)
               errors.push(Array.new([1101, "Authentication failed"]))
               status = 401
            else
               if dev.user_id != Dev.first.user_id
                  errors.push(Array.new([1102, "Action not allowed"]))
                  status = 403
               else
                  if User.exists?(email: email)
                     errors.push(Array.new([2702, "Field already taken: email"]))
                     status = 400
                  else
                     # Validate the fields
                     if !validate_email(email)
                        errors.push(Array.new([2401, "Field not valid: email"]))
                        status = 400
                     end
                     
                     if password.length < min_password_length
                        errors.push(Array.new([2202, "Field too short: password"]))
                        status = 400
                     end
                     
                     if password.length > max_password_length
                        errors.push(Array.new([2302, "Field too long: password"]))
                        status = 400
                     end
                     
                     if username.length < min_username_length
                        errors.push(Array.new([2201, "Field too short: username"]))
                        status = 400
                     end
                     
                     if username.length > max_username_length
                        errors.push(Array.new([2301, "Field too long: username"]))
                        status = 400
                     end
                     
                     if User.exists?(username: username)
                        errors.push(Array.new([2701, "Field already taken: username"]))
                        status = 400
                     end
                     
                     if errors.length == 0
                        @user = User.new(email: email, password: password, username: username)
                        # Save the new user
                        @user.email_confirmation_token = generate_token
								
                        if !@user.save
                           errors.push(Array.new([1103, "Unknown validation error"]))
                           status = 500
                        else
                           SendVerificationEmailWorker.perform_async(@user)
                           ok = true
                        end
                     end
                  end
               end
            end
         end
      end
      
      if ok && errors.length == 0
         status = 201
         @result = @user
      else
         @result.clear
         @result["errors"] = errors
      end
      
      render json: @result, status: status if status
   end
   
   def login
      email = params[:email]
      password = params[:password]
      
      auth = request.headers['HTTP_AUTHORIZATION'].to_s.length < 2 ? params["auth"].to_s.split(' ').last : request.headers['HTTP_AUTHORIZATION'].to_s.split(' ').last
      
      if auth
         api_key = auth.split(",")[0]
         sig = auth.split(",")[1]
      end
      
      errors = Array.new
      @result = Hash.new
      ok = false
      
      if !email || email.length < 1
         errors.push(Array.new([2106, "Missing field: email"]))
         status = 400
      end
      
      if !password || password.length < 1
         errors.push(Array.new([2107, "Missing field: password"]))
         status = 400
      end
      
      if !auth || auth.length < 1
         errors.push(Array.new([2101, "Missing field: auth"]))
         status = 401
      end
      
      if errors.length == 0
         dev = Dev.find_by(api_key: api_key)
         
         if !dev     # Check if the dev exists
            errors.push(Array.new([2802, "Resource does not exist: Dev"]))
            status = 400
         else
            user = User.find_by(email: email)
            
            if !user
               errors.push(Array.new([2801, "Resource does not exist: User"]))
               status = 400
            else
               if !check_authorization(api_key, sig)
                  errors.push(Array.new([1101, "Authentication failed"]))
                  status = 401
               else
                  if !user.authenticate(password)
                     errors.push(Array.new([1201, "Password is incorrect"]))
                     status = 401
                  else
                     if !user.confirmed
                        errors.push(Array.new([1202, "User is not confirmed"]))
                        status = 400
                     else
                        ok = true
                     end
                  end
               end
            end
         end
      end
      
      if ok && errors.length == 0
         # Create JWT and result
         expHours = Rails.env.production? ? 7000 : 10000000
         exp = Time.now.to_i + expHours * 3600
         payload = {:email => user.email, :username => user.username, :user_id => user.id, :dev_id => dev.id, :exp => exp}
         token = JWT.encode payload, ENV['JWT_SECRET'], ENV['JWT_ALGORITHM']
         @result["jwt"] = token
         @result["user_id"] = user.id
         
         status = 200
      else
         @result.clear
         @result["errors"] = errors
      end
      
      render json: @result, status: status if status
   end

   def login_by_jwt
      api_key = params[:api_key]

      jwt = request.headers['HTTP_AUTHORIZATION'].to_s.length < 2 ? params["jwt"].to_s.split(' ').last : request.headers['HTTP_AUTHORIZATION'].to_s.split(' ').last

      errors = Array.new
      @result = Hash.new
      ok = false

      if !jwt || jwt.length < 1
         errors.push(Array.new([2102, "Missing field: jwt"]))
         status = 400
      end

      if !api_key || api_key.length < 1
         errors.push(Array.new([2118, "Missing field: api_key"]))
         status = 400
      end

      if errors.length == 0
         jwt_valid = false
         begin
            decoded_jwt = JWT.decode jwt, ENV['JWT_SECRET'], true, { :algorithm => ENV['JWT_ALGORITHM'] }
            jwt_valid = true
         rescue JWT::ExpiredSignature
            # JWT expired
            errors.push(Array.new([1301, "JWT: expired"]))
            status = 401
         rescue JWT::DecodeError
            errors.push(Array.new([1302, "JWT: not valid"]))
            status = 401
            # rescue other errors
         rescue Exception
            errors.push(Array.new([1303, "JWT: unknown error"]))
            status = 401
         end

         if jwt_valid
            user_id = decoded_jwt[0]["user_id"]
            dev_id = decoded_jwt[0]["dev_id"]
            
            user = User.find_by_id(user_id)
            
            if !user
               errors.push(Array.new([2801, "Resource does not exist: User"]))
               status = 400
            else
               dev_jwt = Dev.find_by_id(dev_id)
               
               if !dev_jwt
                  errors.push(Array.new([2802, "Resource does not exist: Dev"]))
                  status = 400
               else
                  if dev_jwt != Dev.first
                     errors.push(Array.new([1102, "Action not allowed"]))
                     status = 403
                  else
                     dev_api_key = Dev.find_by(api_key: api_key)

                     if !dev_api_key
                        errors.push(Array.new([2802, "Resource does not exist: Dev"]))
                        status = 400
                     else
                        ok = true
                     end
                  end
               end
            end
         end
      end

      if ok && errors.length == 0
         # Create JWT and result
         expHours = Rails.env.production? ? 7000 : 10000000
         exp = Time.now.to_i + expHours * 3600
         payload = {:email => user.email, :username => user.username, :user_id => user.id, :dev_id => dev_api_key.id, :exp => exp}
         token = JWT.encode payload, ENV['JWT_SECRET'], ENV['JWT_ALGORITHM']
         @result["jwt"] = token
         @result["user_id"] = user.id
         
         status = 200
      else
         @result.clear
         @result["errors"] = errors
      end
      
      render json: @result, status: status if status
   end
   
   def get_user
      requested_user_id = params["id"]
      jwt = request.headers['HTTP_AUTHORIZATION'].to_s.length < 2 ? params["jwt"].to_s.split(' ').last : request.headers['HTTP_AUTHORIZATION'].to_s.split(' ').last
      
      errors = Array.new
      @result = Hash.new
      ok = false
      
      if !requested_user_id
         errors.push(Array.new([2104, "Missing field: user_id"]))
         status = 400
      end
      
      if !jwt || jwt.length < 1
         errors.push(Array.new([2102, "Missing field: jwt"]))
         status = 401
      end
      
      if errors.length == 0
         jwt_valid = false
         begin
            decoded_jwt = JWT.decode jwt, ENV['JWT_SECRET'], true, { :algorithm => ENV['JWT_ALGORITHM'] }
            jwt_valid = true
         rescue JWT::ExpiredSignature
            # JWT expired
            errors.push(Array.new([1301, "JWT: expired"]))
            status = 401
         rescue JWT::DecodeError
            errors.push(Array.new([1302, "JWT: not valid"]))
            status = 401
            # rescue other errors
         rescue Exception
            errors.push(Array.new([1303, "JWT: unknown error"]))
            status = 401
         end
         
         if jwt_valid
            user_id = decoded_jwt[0]["user_id"]
            dev_id = decoded_jwt[0]["dev_id"]
            
            user = User.find_by_id(user_id)
            
            if !user
               errors.push(Array.new([2801, "Resource does not exist: User"]))
               status = 400
            else
               dev = Dev.find_by_id(dev_id)
               
               if !dev
                  errors.push(Array.new([2802, "Resource does not exist: Dev"]))
                  status = 400
               else
                  requested_user = User.find_by_id(requested_user_id)
                  
                  if !requested_user
                     errors.push(Array.new([2801, "Resource does not exist: User"]))
                     status = 404
                  else
                     # Check if the logged in user is the requested user
                     if requested_user.id != user.id
                        errors.push(Array.new([1102, "Action not allowed"]))
                        status = 403
                     else
                        @result = requested_user.attributes.except("email_confirmation_token", "password_confirmation_token", "new_password", "password_digest")
                        avatar = get_users_avatar(user.id)
                        @result["avatar"] = avatar["url"]
                        @result["avatar_etag"] = avatar["etag"]
                        @result["total_storage"] = get_total_storage_of_user(user.id)
                        @result["used_storage"] = get_used_storage_of_user(user.id)

                        users_apps = Array.new
                        requested_user.apps.each do |app|
                           app_hash = app.attributes
                           app_hash["used_storage"] = get_used_storage_by_app(app.id, requested_user.id)
                           users_apps.push(app_hash)
                        end
                        @result["apps"] = users_apps

                        ok = true
                     end
                  end
               end
            end
         end
      end
      
      if ok && errors.length == 0
         status = 200
      else
         @result.clear
         @result["errors"] = errors
      end
      
      render json: @result, status: status if status
   end

   def get_user_by_jwt
      jwt = request.headers['HTTP_AUTHORIZATION'].to_s.length < 2 ? params["jwt"].to_s.split(' ').last : request.headers['HTTP_AUTHORIZATION'].to_s.split(' ').last
      
      errors = Array.new
      @result = Hash.new
      ok = false

      if !jwt || jwt.length < 1
         errors.push(Array.new([2102, "Missing field: jwt"]))
         status = 401
      end

      if errors.length == 0
         jwt_valid = false
         begin
            decoded_jwt = JWT.decode jwt, ENV['JWT_SECRET'], true, { :algorithm => ENV['JWT_ALGORITHM'] }
            jwt_valid = true
         rescue JWT::ExpiredSignature
            # JWT expired
            errors.push(Array.new([1301, "JWT: expired"]))
            status = 401
         rescue JWT::DecodeError
            errors.push(Array.new([1302, "JWT: not valid"]))
            status = 401
            # rescue other errors
         rescue Exception
            errors.push(Array.new([1303, "JWT: unknown error"]))
            status = 401
         end

         if jwt_valid
            user_id = decoded_jwt[0]["user_id"]
            dev_id = decoded_jwt[0]["dev_id"]

            user = User.find_by_id(user_id)

            if !user
               errors.push(Array.new([2801, "Resource does not exist: User"]))
               status = 400
            else
               dev = Dev.find_by_id(dev_id)
               
               if !dev
                  errors.push(Array.new([2802, "Resource does not exist: Dev"]))
                  status = 400
               else
                  @result = user.attributes.except("email_confirmation_token", "password_confirmation_token", "new_password", "password_digest")
                  avatar = get_users_avatar(user.id)
                  @result["avatar"] = avatar["url"]
                  @result["avatar_etag"] = avatar["etag"]
                  @result["total_storage"] = get_total_storage_of_user(user.id)
                  @result["used_storage"] = get_used_storage_of_user(user.id)

                  users_apps = Array.new
                  user.apps.each do |app|
                     app_hash = app.attributes
                     app_hash["used_storage"] = get_used_storage_by_app(app.id, user.id)
                     users_apps.push(app_hash)
                  end
                  @result["apps"] = users_apps

                  ok = true
               end
            end
         end
      end

      if ok && errors.length == 0
         status = 200
      else
         @result.clear
         @result["errors"] = errors
      end
      
      render json: @result, status: status if status
   end
   
   define_method :update_user do
      jwt = request.headers['HTTP_AUTHORIZATION'].to_s.length < 2 ? params["jwt"].to_s.split(' ').last : request.headers['HTTP_AUTHORIZATION'].to_s.split(' ').last
      
      errors = Array.new
      @result = Hash.new
      ok = false
      
      if !jwt || jwt.length < 1
         errors.push(Array.new([2102, "Missing field: jwt"]))
         status = 401
      end
      
      if errors.length == 0
         jwt_valid = false
         begin
            decoded_jwt = JWT.decode jwt, ENV['JWT_SECRET'], true, { :algorithm => ENV['JWT_ALGORITHM'] }
            jwt_valid = true
         rescue JWT::ExpiredSignature
            # JWT expired
            errors.push(Array.new([1301, "JWT: expired"]))
            status = 401
         rescue JWT::DecodeError
            errors.push(Array.new([1302, "JWT: not valid"]))
            status = 401
            # rescue other errors
         rescue Exception
            errors.push(Array.new([1303, "JWT: unknown error"]))
            status = 401
         end
         
         if jwt_valid
            user_id = decoded_jwt[0]["user_id"]
            dev_id = decoded_jwt[0]["dev_id"]
            
            user = User.find_by_id(user_id)
            
            if !user
               errors.push(Array.new([2801, "Resource does not exist: User"]))
               status = 400
            else
               dev = Dev.find_by_id(dev_id)
               
               if !dev
                  errors.push(Array.new([2802, "Resource does not exist: Dev"]))
                  status = 400
               else
                  # Check if the call was made from the website
                  if dev != Dev.first
                     errors.push(Array.new([1102, "Action not allowed"]))
                     status = 403
                  else
                     if request.headers["Content-Type"] != "application/json" && request.headers["Content-Type"] != "application/json; charset=utf-8"
                        errors.push(Array.new([1104, "Content-type not supported"]))
                        status = 415
                     else
                        email_changed = false
                        password_changed = false
                        object = request.request_parameters
                        
                        email = object["email"]
                        if email && email.length > 0
                           if !validate_email(email)
                              errors.push(Array.new([2401, "Field not valid: email"]))
                              status = 400
                           end
                           
                           if errors.length == 0
                              # Set email_confirmation_token and send email
                              user.new_email = email
                              user.email_confirmation_token = generate_token
                              email_changed = true
                           end
                        end
                        
                        username = object["username"]
                        if username && username.length > 0
                           if username.length < min_username_length
                              errors.push(Array.new([2201, "Field too short: username"]))
                              status = 400
                           end
                           
                           if username.length > max_username_length
                              errors.push(Array.new([2301, "Field too long: username"]))
                              status = 400
                           end
                           
                           if User.exists?(username: username)
                              errors.push(Array.new([2701, "Field already taken: username"]))
                              status = 400
                           end
                           
                           if errors.length == 0
                              user.username = username
                           end
                        end
                        
                        password = object["password"]
                        if password && password.length > 0
                           if password.length < min_password_length
                              errors.push(Array.new([2202, "Field too short: password"]))
                              status = 400
                           end
                           
                           if password.length > max_password_length
                              errors.push(Array.new([2302, "Field too long: password"]))
                              status = 400
                           end
                           
                           if errors.length == 0
                              # Set password_confirmation_token and send email
                              user.new_password = password
                              user.password_confirmation_token = generate_token
                              password_changed = true
                           end
                        end

                        avatar = object["avatar"]
                        if avatar && avatar.length > 0
                           if errors.length == 0
                              begin
                                 filename = user.id.to_s + ".png"
                                 bytes = Base64.decode64(avatar)
                                 img   = Magick::Image.from_blob(bytes).first
                                 format   = img.format

                                 if format == "png" || format == "PNG" || format == "jpg" || format == "JPG" || format == "jpeg" || format == "JPEG"
                                    # file extension okay
                                    png_bytes = img.to_blob { |attrs| attrs.format = 'PNG' }

                                    Azure.config.storage_account_name = ENV["AZURE_STORAGE_ACCOUNT"]
                                    Azure.config.storage_access_key = ENV["AZURE_STORAGE_ACCESS_KEY"]

                                    client = Azure::Blob::BlobService.new
                                    blob = client.create_block_blob(ENV["AZURE_AVATAR_CONTAINER_NAME"], filename, png_bytes)
                                 else
                                    errors.push(Array.new([1109, "File extension not supported"]))
                                    status = 400
                                 end
                              rescue Exception => e
                                 errors.push(Array.new([1103, "Unknown validation error"]))
                                 status = 400
                              end
                           end
                        end

                        plan = object["plan"]
                        if plan
                           if plan == "0" || plan == "1" || plan == "2"
                              if errors.length == 0
                                 user.plan = plan.to_i
                              end
                           else
                              errors.push(Array.new([1108, "Plan does not exist"]))
                              status = 400
                           end
                        end
                        
                        
                        
                        if errors.length == 0
                           # Update user with new properties
                           if !user.save
                              errors.push(Array.new([1103, "Unknown validation error"]))
                              status = 500
                           else
                              @result = user.attributes.except("email_confirmation_token", "password_confirmation_token", "new_password", "password_digest")
                              avatar = get_users_avatar(user.id)
                              @result["avatar"] = avatar["url"]
                              @result["avatar_etag"] = avatar["etag"]
                              @result["total_storage"] = get_total_storage_of_user(user.id)
                              @result["used_storage"] = get_used_storage_of_user(user.id)

                              users_apps = Array.new
                              user.users_apps.each {|app| users_apps.push(app.app)}
                              @result["apps"] = users_apps

                              ok = true
                              
                              if email_changed
                                 SendChangeEmailEmailWorker.perform_async(user)
                              end
                              
										if password_changed
											SendChangePasswordEmailWorker.perform_async(user)
                              end
                           end
                        end
                     end
                  end
               end
            end
         end
      end
      
      if ok && errors.length == 0
         status = 200
      else
         @result.clear
         @result["errors"] = errors
      end
      
      render json: @result, status: status if status
   end
   
   def delete_user
      email_confirmation_token = params[:email_confirmation_token]
      password_confirmation_token = params[:password_confirmation_token]
      user_id = params[:id]

      errors = Array.new
      @result = Hash.new
      ok = false
      
      if !email_confirmation_token || email_confirmation_token.length < 1
         errors.push(Array.new([2108, "Missing field: email_confirmation_token"]))
         status = 400
      end

      if !password_confirmation_token || password_confirmation_token.length < 1
         errors.push(Array.new([2109, "Missing field: password_confirmation_token"]))
         status = 400
      end

      if !user_id
         errors.push(Array.new([2104, "Missing field: user_id"]))
         status = 400
      end
      
      if errors.length == 0
         user = User.find_by_id(user_id)
         
         if !user
            errors.push(Array.new([2801, "Resource does not exist: User"]))
            status = 400
         else
            if user.email_confirmation_token != email_confirmation_token
               errors.push(Array.new([1204, "Email confirmation token is not correct"]))
               status = 400
            else
               if user.password_confirmation_token != password_confirmation_token
                  errors.push(Array.new([1203, "Password confirmation token is not correct"]))
                  status = 400
               else
                  # Delete the avatar of the user
                  delete_avatar(user.id)

                  # Delete the user
                  user.destroy!
                  @result = {}
                  ok = true
               end
            end
         end
      end
      
      if ok && errors.length == 0
         status = 200
      else
         @result.clear
         @result["errors"] = errors
      end
      
      render json: @result, status: status if status
   end

   def remove_app
      jwt = request.headers['HTTP_AUTHORIZATION'].to_s.length < 2 ? params["jwt"].to_s.split(' ').last : request.headers['HTTP_AUTHORIZATION'].to_s.split(' ').last
      app_id = params["app_id"]

      errors = Array.new
      @result = Hash.new
      ok = false

      if !jwt || jwt.length < 1
         errors.push(Array.new([2102, "Missing field: jwt"]))
         status = 401
      end

      if !app_id
         errors.push(Array.new([2103, "Missing field: id"]))
         status = 400
      end

      if errors.length == 0
         if errors.length == 0
            jwt_valid = false
            begin
               decoded_jwt = JWT.decode jwt, ENV['JWT_SECRET'], true, { :algorithm => ENV['JWT_ALGORITHM'] }
               jwt_valid = true
            rescue JWT::ExpiredSignature
               # JWT expired
               errors.push(Array.new([1301, "JWT: expired"]))
               status = 401
            rescue JWT::DecodeError
               errors.push(Array.new([1302, "JWT: not valid"]))
               status = 401
               # rescue other errors
            rescue Exception
               errors.push(Array.new([1303, "JWT: unknown error"]))
               status = 401
            end
            
            if jwt_valid
               user_id = decoded_jwt[0]["user_id"]
               dev_id = decoded_jwt[0]["dev_id"]
               
               user = User.find_by_id(user_id)
               
               if !user
                  errors.push(Array.new([2801, "Resource does not exist: User"]))
                  status = 400
               else
                  dev = Dev.find_by_id(dev_id)
                  
                  if !dev
                     errors.push(Array.new([2802, "Resource does not exist: Dev"]))
                     status = 400
                  else
                     app = App.find_by_id(app_id)

                     if !app
                        errors.push(Array.new([2803, "Resource does not exist: App"]))
                        status = 400
                     else
                        if dev != Dev.first
                           errors.push(Array.new([1102, "Action not allowed"]))
                           status = 403
                        else
                           # Delete user app association
                           ua = UsersApp.find_by(user_id: user_id, app_id: app_id)
                           if ua
                              ua.destroy!
                           end

                           RemoveAppWorker.perform_async(user.id, app.id)

                           @result = {}
                           ok = true
                        end
                     end
                  end
               end
            end
         end
      end

      if ok && errors.length == 0
         status = 200
      else
         @result.clear
         @result["errors"] = errors
      end
      
      render json: @result, status: status if status
   end
   
   def confirm_user
      email_confirmation_token = params["email_confirmation_token"]
      user_id = params["id"]
      
      errors = Array.new
      @result = Hash.new
      ok = false
      
      if !email_confirmation_token || email_confirmation_token.length < 1
         errors.push(Array.new([2108, "Missing field: email_confirmation_token"]))
         status = 400
      end
      
      if !user_id
         errors.push(Array.new([2103, "Missing field: id"]))
         status = 400
      end
      
      if errors.length == 0
         user = User.find_by_id(user_id)
         
         if !user
            errors.push(Array.new([2801, "Resource does not exist: User"]))
            status = 400
         else
            if user.confirmed == true
               errors.push(Array.new([1106, "User is already confirmed"]))
               status = 400
            else
               if user.email_confirmation_token != email_confirmation_token
                  errors.push(Array.new([1204, "Email confirmation token is not correct"]))
                  status = 400
               else
                  user.email_confirmation_token = nil
                  user.confirmed = true
                  user.save!
                  
                  ok = true
               end
            end
         end
      end
      
      if ok && errors.length == 0
         status = 200
      else
         @result.clear
         @result["errors"] = errors
      end
      
      render json: @result, status: status if status
   end
   
   def send_verification_email
      email = params["email"]
      
      errors = Array.new
      @result = Hash.new
      ok = false
      
      if !email || email.length < 1
         errors.push(Array.new([2106, "Missing field: email"]))
         status = 400
      end
      
      if errors.length == 0
         user = User.find_by(email: email)
         
         if !user
            errors.push(Array.new([2801, "Resource does not exist: User"]))
            status = 400
         else
            if user.confirmed == true
               errors.push(Array.new([1106, "User is already confirmed"]))
               status = 400
            else
               user.email_confirmation_token = generate_token
               if !user.save
                  errors.push(Array.new([1103, "Unknown validation error"]))
                  status = 500
               else
                  ok = true
               end
            end
         end
      end
      
      if ok && errors.length == 0
         status = 200
			# Send email
			SendVerificationEmailWorker.perform_async(user)
      else
         @result.clear
         @result["errors"] = errors
      end
      
      render json: @result, status: status if status
   end

   def send_delete_account_email
      email = params["email"]

      errors = Array.new
      @result = Hash.new
      ok = false
      
      if !email || email.length < 1
         errors.push(Array.new([2106, "Missing field: email"]))
         status = 400
      end

      if errors.length == 0
         user = User.find_by(email: email)
         
         if !user
            errors.push(Array.new([2801, "Resource does not exist: User"]))
            status = 400
         else
            # Generate password and email confirmation tokens
            user.password_confirmation_token = generate_token
            user.email_confirmation_token = generate_token
            
            if !user.save
               errors.push(Array.new([1103, "Unknown validation error"]))
               status = 500
            else
               ok = true
            end
         end
      end

      if ok && errors.length == 0
         status = 200
			# Send email
			SendDeleteAccountEmailWorker.perform_async(user)
      else
         @result.clear
         @result["errors"] = errors
      end
      
      render json: @result, status: status if status
   end
   
   def send_reset_password_email
      email = params["email"]
      
      errors = Array.new
      @result = Hash.new
      ok = false
      
      if !email || email.length < 1
         errors.push(Array.new([2106, "Missing field: email"]))
         status = 400
      end
      
      if errors.length == 0
         user = User.find_by(email: email)
         
         if !user
            errors.push(Array.new([2801, "Resource does not exist: User"]))
            status = 400
         else
            # Generate password confirmation token
            user.password_confirmation_token = generate_token
            if !user.save
               errors.push(Array.new([1103, "Unknown validation error"]))
               status = 500
            else
               ok = true
            end
         end
      end
      
      if ok && errors.length == 0
         status = 200
			# Send email
			SendResetPasswordEmailWorker.perform_async(user)
      else
         @result.clear
         @result["errors"] = errors
      end
      
      render json: @result, status: status if status
   end
   
   define_method :set_password do
      password_confirmation_token = params["password_confirmation_token"]
      password = params["password"]

      errors = Array.new
      @result = Hash.new
      ok = false

      if !password_confirmation_token || password_confirmation_token.length < 1
         errors.push(Array.new([2109, "Missing field: password_confirmation_token"]))
         status = 400
      end

      if !password || password.length < 1
         errors.push(Array.new([2107, "Missing field: password"]))
         status = 400
      end

      if errors.length == 0
         user = User.find_by(password_confirmation_token: password_confirmation_token)

         if !user
            errors.push(Array.new([1203, "Password confirmation token is not correct"]))
            status = 400
         else
            # Validate password
            if password.length < min_password_length
               errors.push(Array.new([2202, "Field too short: password"]))
               status = 400
            end
            
            if password.length > max_password_length
               errors.push(Array.new([2302, "Field too long: password"]))
               status = 400
            end
            
            if errors.length == 0
               user.password = password
               user.password_confirmation_token = nil

               if !user.save
                  errors.push(Array.new([1103, "Unknown validation error"]))
                  status = 500
               else
                  ok = true
               end
            end
         end
      end

      if ok && errors.length == 0
         status = 200
      else
         @result.clear
         @result["errors"] = errors
      end
      
      render json: @result, status: status if status
   end

   def save_new_password
      user_id = params["id"]
      password_confirmation_token = params["password_confirmation_token"]
      
      errors = Array.new
      @result = Hash.new
      ok = false
      
      if !user_id
         errors.push(Array.new([2103, "Missing field: id"]))
         status = 400
      end
      
      if !password_confirmation_token || password_confirmation_token.length < 1
         errors.push(Array.new([2109, "Missing field: password_confirmation_token"]))
         status = 400
      end
      
      if errors.length == 0
         user = User.find_by_id(user_id)
         
         if !user
            errors.push(Array.new([2801, "Resource does not exist: User"]))
            status = 400
         else
            if password_confirmation_token != user.password_confirmation_token
               errors.push(Array.new([1203, "Password confirmation token is not correct"]))
               status = 400
            else
               if user.new_password == nil || user.new_password.length < 1
                  errors.push(Array.new([2603, "Field is empty: new_password"]))
                  status = 400
               else
                  # Save new password
                  user.password = user.new_password
                  user.new_password = nil
                  
                  user.password_confirmation_token = nil
                  
                  if !user.save
                     errors.push(Array.new([1103, "Unknown validation error"]))
                     status = 500
                  else
                     ok = true
                  end
               end
            end
         end
      end
      
      if ok && errors.length == 0
         status = 200
      else
         @result.clear
         @result["errors"] = errors
      end
      
      render json: @result, status: status if status
   end
   
   def save_new_email
      user_id = params["id"]
      email_confirmation_token = params["email_confirmation_token"]
      
      errors = Array.new
      @result = Hash.new
      ok = false
      
      if !user_id
         errors.push(Array.new([2103, "Missing field: id"]))
         status = 400
      end
      
      if !email_confirmation_token || email_confirmation_token.length < 1
         errors.push(Array.new([2108, "Missing field: email_confirmation_token"]))
         status = 400
      end
      
      if errors.length == 0
         user = User.find_by_id(user_id)
         
         if !user
            errors.push(Array.new([2801, "Resource does not exist: User"]))
            status = 400
         else
            if email_confirmation_token != user.email_confirmation_token
               errors.push(Array.new([1204, "Email confirmation token is not correct"]))
               status = 400
            else
               if user.new_email == nil || user.new_email.length < 1
                  errors.push(Array.new([2601, "Field is empty: new_email"]))
                  status = 400
               else
                  # Save new email
                  user.old_email = user.email
                  user.email = user.new_email
                  user.new_email = nil
                  
                  user.email_confirmation_token = nil
                  
                  if !user.save
                     errors.push(Array.new([1103, "Unknown validation error"]))
                     status = 500
                  else
                     ok = true
                  end
               end
            end
         end
      end
      
      if ok && errors.length == 0
			status = 200
			SendResetNewEmailEmailWorker.perform_async(user)
      else
         @result.clear
         @result["errors"] = errors
      end
      
      render json: @result, status: status if status
   end
   
   def reset_new_email
      # This method exists to reset the new email, when the email change was not intended by the account owner
      user_id = params["id"]
      
      errors = Array.new
      @result = Hash.new
      ok = false
      
      if !user_id
         errors.push(Array.new([2103, "Missing field: id"]))
         status = 400
      end
      
      if errors.length == 0
         user = User.find_by_id(user_id)
         
         if !user
            errors.push(Array.new([2801, "Resource does not exist: User"]))
            status = 400
         else
            if !user.old_email || user.old_email.length < 1
               errors.push(Array.new([2602, "Field is empty: old_email"]))
               status = 400
            else
               # set new_email to email and email to old_email
               user.email = user.old_email
               user.old_email = nil
               
               if !user.save
                  errors.push(Array.new([1103, "Unknown validation error"]))
                  status = 500
               else
                  ok = true
               end
            end
         end
      end
      
      if ok && errors.length == 0
         status = 200
      else
         @result.clear
         @result["errors"] = errors
      end
      
      render json: @result, status: status if status
	end
	
	def export_data
		jwt = request.headers['HTTP_AUTHORIZATION'].to_s.length < 2 ? params["jwt"].to_s.split(' ').last : request.headers['HTTP_AUTHORIZATION'].to_s.split(' ').last
		
		errors = Array.new
      @result = Hash.new
		ok = false
		
		if !jwt || jwt.length < 1
         errors.push(Array.new([2102, "Missing field: jwt"]))
         status = 401
		end
		
		if errors.length == 0
			jwt_valid = false
         begin
            decoded_jwt = JWT.decode jwt, ENV['JWT_SECRET'], true, { :algorithm => ENV['JWT_ALGORITHM'] }
            jwt_valid = true
         rescue JWT::ExpiredSignature
            # JWT expired
            errors.push(Array.new([1301, "JWT: expired"]))
            status = 401
         rescue JWT::DecodeError
            errors.push(Array.new([1302, "JWT: not valid"]))
            status = 401
            # rescue other errors
         rescue Exception
            errors.push(Array.new([1303, "JWT: unknown error"]))
            status = 401
			end
			
			if jwt_valid
				user_id = decoded_jwt[0]["user_id"]
				dev_id = decoded_jwt[0]["dev_id"]
				
				user = User.find_by_id(user_id)

				if !user
					errors.push(Array.new([2801, "Resource does not exist: User"]))
               status = 400
				else
					dev = Dev.find_by_id(dev_id)

					if !dev
                  errors.push(Array.new([2802, "Resource does not exist: Dev"]))
                  status = 400
					else
						# Check if the call was made from the website
                  if dev != Dev.first
                     errors.push(Array.new([1102, "Action not allowed"]))
                     status = 403
						else
							@result = export(user.id)

							ok = true
						end
					end
				end
			end
		end

		if ok && errors.length == 0
         status = 200
      else
         @result.clear
         @result["errors"] = errors
      end
      
      render json: @result, status: status if status
	end

	def export(user_id)
		user = User.find_by_id(user_id)

		if user
			root_hash = Hash.new

			# Get the user data
			user_data = Hash.new
			user_data["email"] = user.email
			user_data["username"] = user.username
			user_data["new_email"] = user.new_email
			user_data["old_email"] = user.old_email
			user_data["plan"] = user.plan
			user_data["created_at"] = user.created_at
			user_data["updated_at"] = user.updated_at

			root_hash["user"] = user_data

			apps_array = Array.new
			files_array = Array.new		# Contains the info of the file in the form of a hash with ext and uuid

			# Loop through all apps of the user
			user.apps.each do |app|
				app_hash = Hash.new
				table_array = Array.new

				app_hash["id"] = app.id
				app_hash["name"] = app.name

				# Loop through all tables of each app
				app.tables.each do |table|
					table_hash = Hash.new
					object_array = Array.new

					table_hash["id"] = table.id
					table_hash["name"] = table.name

					# Find all table_objects of the user in the table
					table.table_objects.where(user_id: user.id).each do |obj|
						object_hash = Hash.new
						property_hash = Hash.new

						object_hash["id"] = obj.id
						object_hash["uuid"] = obj.uuid
						object_hash["visibility"] = obj.visibility # TODO: Change to string
						object_hash["file"] = obj.file

						# If the object is a file, save the info for later
						if obj.file && obj.properties.where(name: "ext").count > 0
							file_object = Hash.new
							file_object["ext"] = obj.properties.where(name: "ext").first.value
							file_object["id"] = obj.id
							file_object["app_id"] = app.id
							files_array.push(file_object)
						end

						# Get the properties of the table_object
						obj.properties.each do |prop|
							property_hash[prop.name] = prop.value
						end

						object_hash["properties"] = property_hash
						object_array.push(object_hash)
					end

					table_hash["table_objects"] = object_array
					table_array.push(table_hash)
				end

				app_hash["tables"] = table_array
				apps_array.push(app_hash)
			end

			root_hash["apps"] = apps_array

			require 'ZipFileGenerator'
			require 'open-uri'

			# Create the necessary export directories
			# TODO: Add id of the archive in the DB to the file name
			exportZipFilePath = "/tmp/dav-export.zip"
			exportFolderPath = "/tmp/dav-export/"
			filesExportFolderPath = exportFolderPath + "files/"
			dataExportFolderPath = exportFolderPath + "data/"
			sourceExportFolderPath = exportFolderPath + "source/"

			# Delete the old zip file and the folder
			FileUtils.rm_rf(Dir.glob(exportFolderPath + "*"))
			File.delete(exportZipFilePath) if File.exists?(exportZipFilePath)

			# Create the directories
			Dir.mkdir(exportFolderPath) unless File.exists?(exportFolderPath)
			Dir.mkdir(filesExportFolderPath) unless File.exists?(filesExportFolderPath)
			Dir.mkdir(dataExportFolderPath) unless File.exists?(dataExportFolderPath)
			Dir.mkdir(sourceExportFolderPath) unless File.exists?(sourceExportFolderPath)

			# Download the avatar
			avatar = get_users_avatar(user_id)

			open(filesExportFolderPath + "avatar.png", 'wb') do |file|
				file << open(avatar["url"]).read
			end

			# Download all files
			files_array.each do |file|
				download_blob(file["app_id"], file["id"], file["ext"], filesExportFolderPath)
			end

			# Create the json file
			File.open(dataExportFolderPath + "data.json", "w") { |f| f.write(root_hash.to_json) }

			# Copy the contents of the source folder
			FileUtils.cp_r(Rails.root + "lib/dav-export/source/", exportFolderPath)

			# Copy the index.html
			FileUtils.cp(Rails.root + "lib/dav-export/index.html", exportFolderPath)

			# Create the zip file
			zf = ZipFileGenerator.new(exportFolderPath, exportZipFilePath)
			zf.write

			return root_hash.to_json
		end
	end
   
   private
   def generate_token
      SecureRandom.hex(20)
   end
   
   def validate_email(email)
      reg = Regexp.new("[a-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[a-z0-9!#$%&'*+/=?^_`{|}~-]+)*@(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]*[a-z0-9])?")
      return (reg.match(email))? true : false
   end
end