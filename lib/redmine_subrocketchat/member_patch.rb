# lib/redmine_subrocketchat/member_patch.rb

module RedmineSubrocketchat
  module MemberPatch
    extend ActiveSupport::Concern

    included do
      after_create :add_user_to_rocket_chat
      after_destroy :remove_user_from_rocket_chat
    end

    def add_user_to_rocket_chat
      return if user.nil? || user.anonymous?
      return unless project&.module_enabled?(:rocket_chat)

      success = RedmineSubrocketchat::RocketChatHelper.add_member_to_channel(user, "rm_#{project.identifier}")
      unless success
        Rails.logger.error("Rocket.Chat: User #{user.login} could not be added to Rocket.Chat channel.")
      end
    end

    def remove_user_from_rocket_chat
      return if user.nil? || user.anonymous?
      return unless project&.module_enabled?(:rocket_chat)

      RedmineSubrocketchat::RocketChatHelper.remove_member_from_channel(user, "rm_#{project.identifier}")
    end
  end
end
