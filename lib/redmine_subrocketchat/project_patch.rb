# lib/redmine_subrocketchat/project_patch.rb

# Extends the Redmine Project model to integrate Rocket.Chat functionality:
# - Creates, synchronizes, and removes Rocket.Chat channels (`rm_<identifier>`) on project lifecycle events.

module RedmineSubrocketchat
  module ProjectPatch
    extend ActiveSupport::Concern

    included do
      after_create :create_rocket_chat_channel
      after_update :handle_module_changes
      after_destroy :remove_rocket_chat_channel
    end
  end
end if !defined?(RedmineSubrocketchat::ProjectPatch)

module RedmineSubrocketchat
  module ProjectPatch

    def create_rocket_chat_channel
      if enabled_modules.map(&:name).include?('rocket_chat')
        RedmineSubrocketchat::RocketChatHelper.create_rocket_chat_channel(self)
      end
    end

    def handle_module_changes
      if enabled_modules.map(&:name).include?('rocket_chat')
        RedmineSubrocketchat::RocketChatHelper.sync_channel_and_members(self)
      end
    end

    def remove_rocket_chat_channel
      RedmineSubrocketchat::RocketChatHelper.delete_channel("rm_#{identifier}")
    end

    private

    def enabled_modules_was
      changes = saved_changes['enabled_module_names']
      changes ? changes.first : nil
    end
  end
end
