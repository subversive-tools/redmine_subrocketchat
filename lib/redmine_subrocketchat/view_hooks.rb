# lib/redmine_subrocketchat/view_hooks.rb

module RedmineSubrocketchat
  class ViewHooks < Redmine::Hook::ViewListener
    # Checks whether the current user is allowed to see Rocket.Chat (respecting Redmine permissions and Subsimplify)
    # While Rocket.Chat is not configured yet, hide the sidebar/chat UI completely for non-admin users.
    def rocket_chat_allowed?(project)
      return false unless project&.module_enabled?(:rocket_chat)
      return false unless User.current.allowed_to?(:access_chat, project)
      return false unless RedmineSubrocketchat::RocketChatHelper.configured? || User.current.admin?

      if defined?(RedmineSubsimplify::Configuration) && RedmineSubsimplify::Configuration.simplified_user?
        return false unless RedmineSubsimplify::Configuration.allowed_modules.include?('rocket_chat')
      end

      true
    end

    # Adds a contextual "Chat" action link (between Edit and Watch) on the issue detail view (only when configured)
    def view_issues_show_details_bottom(context = {})
      project = context[:project]
      issue = context[:issue]
      return '' unless rocket_chat_allowed?(project) && RedmineSubrocketchat::RocketChatHelper.configured? && issue

      context[:controller].send(:render_to_string, {
        partial: 'rocket_chat/issue_thread_box',
        locals: { project: project, issue: issue }
      })
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

    # When Rocket.Chat is not yet configured, adds a small inline warning & link to plugin settings
    # directly next to the "Rocket chat" module checkbox in Project Settings -> Modules (and New Project)
    def view_projects_form(context = {})
      return '' if RedmineSubrocketchat::RocketChatHelper.configured?

      hint_text = I18n.t('rocketchat.ui.module_unconfigured_short', default: 'nicht konfiguriert')
      link_text = I18n.t('rocketchat.ui.module_settings_link', default: 'Einstellungen')
      is_admin = User.current.admin?

      badge_html = if is_admin
                     %(<small class="rc-module-unconfigured-hint" style="margin-left:4px;font-size:11px;color:#b45309;font-weight:normal;">(⚠ #{ERB::Util.html_escape(hint_text)} – <a href="/settings/plugin/redmine_subrocketchat" style="color:#b45309;text-decoration:underline;">#{ERB::Util.html_escape(link_text)}</a>)</small>)
                   else
                     %(<small class="rc-module-unconfigured-hint" style="margin-left:4px;font-size:11px;color:#b45309;font-weight:normal;">(⚠ #{ERB::Util.html_escape(hint_text)})</small>)
                   end

      <<~HTML.html_safe
        <script>
          (function() {
            function attachRcUnconfiguredHint() {
              var cb = document.getElementById('project_enabled_module_names_rocket_chat') ||
                       document.querySelector('input[name="project[enabled_module_names][]"][value="rocket_chat"]');
              if (!cb || !cb.parentElement) return;
              if (cb.parentElement.querySelector('.rc-module-unconfigured-hint')) return;
              cb.parentElement.insertAdjacentHTML('beforeend', #{badge_html.to_json});
            }
            if (document.readyState === 'loading') {
              document.addEventListener('DOMContentLoaded', attachRcUnconfiguredHint);
            } else {
              attachRcUnconfiguredHint();
            }
          })();
        </script>
      HTML
    end
  end
end
