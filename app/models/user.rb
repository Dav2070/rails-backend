class User < ApplicationRecord
	before_save { self.email = email.downcase }
	after_destroy :delete_avatar

	validates :username, presence: true, uniqueness: {case_sensitive: false},
					length: {minimum: 3, maximum: 25}
	VALID_EMAIL_REGEX = /\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i
	validates :email, presence: true, length: {maximum: 105},
				uniqueness: {case_sensitive: false},
				format: {with: VALID_EMAIL_REGEX}
	has_secure_password
   
	has_one :dev, dependent: :destroy
	has_many :table_objects, dependent: :destroy
	has_many :users_apps, dependent: :destroy
	has_many :apps, through: :users_apps
	has_many :archives, dependent: :destroy

	private
	def delete_avatar
		BlobOperationsService.delete_avatar(self.id)
	end
end