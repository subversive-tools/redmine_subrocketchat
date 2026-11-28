# lib/redmine_subrocketchat/member_patch.rb

module RedmineSubrocketchat
  module MemberPatch
    extend ActiveSupport::Concern

    included do
      after_commit :sync_user_rocket_chat_membership, on: [:create, :update]
      after_destroy :remove_user_from_rocket_chat
    end
  end
end if !defined?(RedmineSubrocketchat::MemberPatch)

module RedmineSubrocketchat
  module MemberPatch

    def sync_user_rocket_chat_membership
      return if user.nil? || user.anonymous?
      return unless project&.module_enabled?(:rocket_chat)
      return unless RedmineSubrocketchat::RocketChatHelper.configured?

      channel_name = "rm_#{project.identifier}"
      if user.allowed_to?(:access_chat, project)
        success = RedmineSubrocketchat::RocketChatHelper.add_member_to_channel(user, channel_name)
        unless success
          Rails.logger.error("Rocket.Chat: User #{user.login} could not be added to Rocket.Chat channel.")
        end
      else
        RedmineSubrocketchat::RocketChatHelper.remove_member_from_channel(user, channel_name)
      end
    end

    def remove_user_from_rocket_chat
      return if user.nil? || user.anonymous?
      return unless project&.module_enabled?(:rocket_chat)
      return unless RedmineSubrocketchat::RocketChatHelper.configured?

      RedmineSubrocketchat::RocketChatHelper.remove_member_from_channel(user, "rm_#{project.identifier}")
    end
  end
end
