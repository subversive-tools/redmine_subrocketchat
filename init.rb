# init.rb - Initialization file for the Redmine Subrocketchat plugin

require_relative 'lib/redmine_subrocketchat/settings_helper'
require_relative 'lib/redmine_subrocketchat/rocket_chat_helper'

Redmine::Plugin.register :redmine_subrocketchat do
  name 'Subrocketchat'
  author 'Stefan Mischke'
  description 'Seamless Rocket.Chat integration for Redmine via EmbeddedChat — featuring a persistent resizable sidebar, #issue live autocomplete, per-issue chat threads, and automatic channel/member synchronization.'
  version '2.0.0'
  url 'https://github.com/subversive-tools/redmine_subrocketchat'
  author_url 'https://github.com/modoq'
  requires_redmine version_or_higher: '4.0.0'

  # Register project module and authorizations for Rocket.Chat
  project_module :rocket_chat do
    permission :access_chat, {
      rocket_chat: [:show, :session_config, :issues, :issue_thread, :proxy]
    }
  end

  # Add Rocket.Chat tab in the project menu
  menu :project_menu, :rocket_chat,
       { controller: 'rocket_chat', action: 'show' },
       caption: proc { I18n.t('rocketchat.init.menu_caption', default: 'Chat') },
       after: :wiki,
       param: :project_id

  # Plugin settings (visible in the Redmine admin panel)
  settings default: {
    'rocket_chat_url' => 'https://your-rocketchat-server.com',
    'rocket_chat_url_internal' => '',
    'rocket_chat_user_id' => '',
    'rocket_chat_token' => '',
    'rocket_chat_token_secret' => '',
    'show_sidebar' => 'true',
    'redmine_host_url' => '',
    'auto_login_users' => 'true',
    'auto_create_users' => 'true',
    'auto_create_issue_threads' => 'false',
    'post_issue_updates_to_thread' => 'true'
  }, partial: 'settings/rocket_chat_settings'
end

# Load hooks, model patches, controller, and routes
require File.expand_path('lib/redmine_subrocketchat/view_hooks', __dir__)
require File.expand_path('lib/redmine_subrocketchat/project_patch', __dir__)
require File.expand_path('lib/redmine_subrocketchat/member_patch', __dir__)
require File.expand_path('lib/redmine_subrocketchat/issue_patch', __dir__)
require File.expand_path('app/controllers/rocket_chat_controller', __dir__)
require File.expand_path('config/routes', __dir__)

# Set up model patches, legacy settings migration, and default role permissions inside `to_prepare`
Rails.configuration.to_prepare do
  Project.include(RedmineSubrocketchat::ProjectPatch) unless Project.included_modules.include?(RedmineSubrocketchat::ProjectPatch)
  Member.include(RedmineSubrocketchat::MemberPatch) unless Member.included_modules.include?(RedmineSubrocketchat::MemberPatch)
  Issue.include(RedmineSubrocketchat::IssuePatch) unless Issue.included_modules.include?(RedmineSubrocketchat::IssuePatch)

  begin
    if ActiveRecord::Base.connection.table_exists?('settings')
      RedmineSubrocketchat::SettingsHelper.migrate_legacy_settings!
    end
  rescue StandardError => e
    Rails.logger.warn("Subrocketchat init: Setup warning (#{e.message})")
  end
end
