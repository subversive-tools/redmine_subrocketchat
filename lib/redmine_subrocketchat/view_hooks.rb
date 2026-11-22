# lib/redmine_subrocketchat/view_hooks.rb

module RedmineSubrocketchat
  class ViewHooks < Redmine::Hook::ViewListener
    # Checks whether the current user is allowed to see Rocket.Chat (respecting Redmine permissions and Subsimplify)
    def rocket_chat_allowed?(project)
      return false unless project&.module_enabled?(:rocket_chat)
      return false unless User.current.allowed_to?(:access_chat, project)

      if defined?(RedmineSubsimplify::Configuration) && RedmineSubsimplify::Configuration.simplified_user?
        return false unless RedmineSubsimplify::Configuration.allowed_modules.include?('rocket_chat')
      end

      true
    end

    # Adds stylesheets and the EmbeddedChat bundle when a project with rocket_chat enabled is in context
    def view_layouts_base_html_head(context = {})
      project = context[:project]
      return '' unless rocket_chat_allowed?(project) && context[:controller].request.path != '/projects/new'

      plugin_settings = Setting.plugin_redmine_subrocketchat
      stylesheet_name = plugin_settings['show_sidebar'] == 'true' ? 'rocketchat_sidebar' : 'rocketchat'

      tags = []
      tags << stylesheet_link_tag(stylesheet_name, plugin: :redmine_subrocketchat)
      tags << javascript_include_tag('rocketchat_embedded', plugin: :redmine_subrocketchat)
      tags.join("\n").html_safe
    end

    # Adds the sidebar at body_bottom (outside #wrapper) so intra-project PJAX navigation can swap #wrapper without reloading the chat
    def view_layouts_base_body_bottom(context = {})
      project = context[:project]
      if rocket_chat_allowed?(project) &&
         Setting.plugin_redmine_subrocketchat['show_sidebar'] == 'true' &&
         context[:controller].request.path != '/projects/new'
        context[:controller].send(:render_to_string, {
          partial: 'rocket_chat/sidebar',
          locals: context
        })
      end
    end

    # Adds a contextual "Chat" action link (between Edit and Watch) on the issue detail view
    def view_issues_show_details_bottom(context = {})
      project = context[:project]
      issue = context[:issue]
      return '' unless rocket_chat_allowed?(project) && issue

      context[:controller].send(:render_to_string, {
        partial: 'rocket_chat/issue_thread_box',
        locals: { project: project, issue: issue }
      })
    end
  end
end
