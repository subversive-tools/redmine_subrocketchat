# lib/redmine_subrocketchat/issue_patch.rb

module RedmineSubrocketchat
  module IssuePatch
    extend ActiveSupport::Concern

    included do
      after_create_commit :create_rocket_chat_thread_on_create
      after_update_commit :notify_rocket_chat_thread_on_update
    end

    def create_rocket_chat_thread_on_create
      return unless project&.module_enabled?(:rocket_chat)
      return unless Setting.plugin_redmine_subrocketchat['auto_create_issue_threads'] == 'true'

      RedmineSubrocketchat::RocketChatHelper.ensure_issue_thread(self)
    rescue StandardError => e
      Rails.logger.error("Rocket.Chat [Issue##{id}]: Error creating thread: #{e.message}")
    end

    def notify_rocket_chat_thread_on_update
      return unless project&.module_enabled?(:rocket_chat)
      return unless Setting.plugin_redmine_subrocketchat['post_issue_updates_to_thread'] == 'true'
      return if rocketchat_thread_id.blank?

      journal = journals.last
      return unless journal && journal.created_on >= 10.seconds.ago

      RedmineSubrocketchat::RocketChatHelper.post_issue_journal_to_thread(self, journal)
    rescue StandardError => e
      Rails.logger.error("Rocket.Chat [Issue##{id}]: Error posting update to thread: #{e.message}")
    end
  end
end
