class Dev < ActiveRecord::Base
   belongs_to :user
   has_many :apps, dependent: :destroy
   
   before_save { generate_keys }
   
   def generate_keys
      self.uuid = SecureRandom.uuid
      self.api_key = SecureRandom.urlsafe_base64(30)
      self.secret_key = SecureRandom.urlsafe_base64(40)
   end
end