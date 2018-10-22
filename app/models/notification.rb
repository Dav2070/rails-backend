class Notification < ApplicationRecord
	belongs_to :app
	belongs_to :user
	has_many :notification_properties, dependent: :destroy
end