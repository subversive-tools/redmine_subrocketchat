# lib/redmine_subrocketchat/issue_patch.rb

module RedmineSubrocketchat
  module IssuePatch
    extend ActiveSupport::Concern

    included do
      after_create_commit :create_rocket_chat_thread_on_create
      after_update_commit :notify_rocket_chat_thread_on_update
    end
  end
end if !defined?(RedmineSubrocketchat::IssuePatch)

module RedmineSubrocketchat
  module IssuePatch

    def create_rocket_chat_thread_on_create
      return unless project&.module_enabled?(:rocket_chat)
      return unless RedmineSubrocketchat::RocketChatHelper.configured?
      return unless Setting.plugin_redmine_subrocketchat['auto_create_issue_threads'] == 'true'
      # Never auto-publish private issues into the shared project channel
      return if respond_to?(:is_private?) && is_private?

      RedmineSubrocketchat::RocketChatHelper.ensure_issue_thread(self)
    rescue StandardError => e
      Rails.logger.error("Rocket.Chat [Issue##{id}]: Error creating thread: #{e.message}")
    end

    def notify_rocket_chat_thread_on_update
      return unless project&.module_enabled?(:rocket_chat)
      return unless RedmineSubrocketchat::RocketChatHelper.configured?
      return unless Setting.plugin_redmine_subrocketchat['post_issue_updates_to_thread'] == 'true'
      return if rocketchat_thread_id.blank?
      return if respond_to?(:is_private?) && is_private?

      journal = journals.last
      return unless journal && journal.created_on >= 10.seconds.ago
      # Never post private notes to the shared Rocket.Chat thread
      return if journal.respond_to?(:private_notes?) && journal.private_notes?

      RedmineSubrocketchat::RocketChatHelper.post_issue_journal_to_thread(self, journal)
    rescue StandardError => e
      Rails.logger.error("Rocket.Chat [Issue##{id}]: Error posting update to thread: #{e.message}")
    end
  end
end
