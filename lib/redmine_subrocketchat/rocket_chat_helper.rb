# lib/redmine_subrocketchat/rocket_chat_helper.rb

# Provides utility methods to integrate Redmine with Rocket.Chat:
# - Creating & managing project channels (private groups `rm_<identifier>`)
# - Synchronizing Redmine project members & auto-provisioning missing users
# - Generating user session tokens (SSO / auto-login for EmbeddedChat)
# - Creating and replying to per-issue Rocket.Chat threads (`tmid`)

require 'net/http'
require 'json'
require 'securerandom'

module RedmineSubrocketchat
  module RocketChatHelper
    class << self
      attr_reader :base_url, :token, :user_id

      # Public: Returns the current plugin settings hash
      def plugin_settings
        Setting.plugin_redmine_subrocketchat || {}
      end

      # Public: Returns the Rocket.Chat channel name for a given project
      def channel_name_for(project)
        "rm_#{project.identifier}"
      end

      # Public: Synchronizes the Rocket.Chat channel and its members with the Redmine project
      def sync_channel_and_members(project)
        channel_name = channel_name_for(project)
        room_id = ensure_channel_exists(channel_name, project)
        sync_members_to_channel(project, channel_name, room_id: room_id)
        room_id
      end

      # Public: Creates a Rocket.Chat channel for the given project and returns its room_id
      def create_rocket_chat_channel(project)
        channel_name = channel_name_for(project)
        room_id = nil
        with_valid_channel(channel_name) do
          response = execute_request(
            'groups.create',
            params: { 'name' => channel_name }
          )
          room_id = response&.dig('group', '_id')
          if room_id
            set_channel_topic(project, room_id)
          else
            log("Failed to create channel '#{channel_name}'", level: :error, context: project.identifier)
          end
        end
        room_id
      end

      # Sets the topic of a Rocket.Chat channel
      def set_channel_topic(project, room_id)
        redmine_url = redmine_base_url
        topic = "☛ [Redmine: #{project.name}](#{redmine_url}/projects/#{project.identifier})"

        response = execute_request(
          'groups.setTopic',
          params: { 'roomId' => room_id, 'topic' => topic }
        )

        if response&.dig('success')
          log("Successfully set the topic for channel '#{room_id}'", context: project.identifier)
        else
          log("Failed to set the topic for channel '#{room_id}'", level: :error, context: project.identifier)
        end
      end

      # Public: Deletes a Rocket.Chat channel by its name
      def delete_channel(channel_name)
        room_id = get_channel_id(channel_name)
        if room_id
          execute_request('groups.delete', params: { 'roomId' => room_id })
        else
          log("Channel '#{channel_name}' does not exist, cannot delete", level: :error)
          false
        end
      end

      # Public: Adds a user to a Rocket.Chat channel (auto-creating the user if enabled)
      def add_member_to_channel(user_or_username, channel_name, room_id: nil)
        user, username = resolve_user(user_or_username)
        ensure_rocket_chat_user(user) if user
        manage_channel_user(:add, username, channel_name, room_id: room_id)
      end

      # Public: Removes a user from a Rocket.Chat channel
      def remove_member_from_channel(user_or_username, channel_name, room_id: nil)
        _, username = resolve_user(user_or_username)
        manage_channel_user(:remove, username, channel_name, room_id: room_id)
      end

      # Manages adding or removing a user in a Rocket.Chat channel
      def manage_channel_user(action, username, channel_name, room_id: nil)
        room_id ||= get_channel_id(channel_name)
        return log("Channel '#{channel_name}' does not exist, cannot #{action} user '#{username}'", level: :error) unless room_id

        rc_user_id = get_user_id(username)
        unless rc_user_id
          log("User '#{username}' not found in Rocket.Chat, cannot #{action} in '#{channel_name}'", level: :error)
          return false
        end

        endpoint = action == :add ? 'groups.invite' : 'groups.kick'
        response = execute_request(
          endpoint,
          params: { 'roomId' => room_id, 'userId' => rc_user_id }
        )

        if response&.dig('success')
          log("Successfully #{action == :add ? 'added' : 'removed'} user '#{username}' in channel '#{channel_name}'", context: room_id)
          true
        else
          log("Failed to #{action == :add ? 'add' : 'remove'} user '#{username}' in channel '#{channel_name}'", level: :error, context: room_id)
          false
        end
      end

      # Public: Retrieves or creates the room_id for a project's channel
      def get_or_create_project_room_id(project)
        channel_name = channel_name_for(project)
        room_id = get_channel_id(channel_name)
        return room_id if room_id.present?

        sync_channel_and_members(project)
      end

      # Public: Retrieves the ID of a Rocket.Chat channel by its name
      def get_channel_id(channel_name)
        response = execute_request(
          "groups.info?roomName=#{URI.encode_www_form_component(channel_name)}",
          http_method: Net::HTTP::Get
        )
        response&.dig('group', '_id')
      end

      # Public: Ensures a Redmine user exists in Rocket.Chat and returns their Rocket.Chat user ID
      def ensure_rocket_chat_user(user)
        return nil if user.nil? || user.anonymous?

        rc_user_id = get_user_id(user.login)
        return rc_user_id if rc_user_id.present?

        return nil unless plugin_settings['auto_create_users'] != 'false'

        email = user.mail.presence || "#{user.login}@redmine.local"
        full_name = user.name.presence || user.login
        random_password = "#{SecureRandom.urlsafe_base64(18)}!A1a"

        log("Creating missing Rocket.Chat user '#{user.login}' (#{email})")
        response = execute_request(
          'users.create',
          params: {
            'username' => user.login,
            'email' => email,
            'name' => full_name,
            'password' => random_password,
            'verified' => true
          }
        )
        response&.dig('user', '_id')
      end

      # Public: Looks up a Rocket.Chat user ID by username
      def get_user_id(username)
        return nil if username.blank?

        response = execute_request(
          "users.info?username=#{URI.encode_www_form_component(username)}",
          http_method: Net::HTTP::Get
        )
        response&.dig('user', '_id')
      end

      # Public: Ensures a specific Rocket.Chat user ID (`rc_user_id`) is invited to the project's Rocket.Chat group
      def ensure_rc_user_id_in_project_channel(rc_user_id, project)
        return false if rc_user_id.blank? || project.nil?

        room_id = get_or_create_project_room_id(project)
        return false if room_id.blank?

        execute_request(
          'groups.invite',
          params: { 'roomId' => room_id, 'userId' => rc_user_id }
        )
        true
      rescue StandardError => e
        log("Could not invite rc_user_id '#{rc_user_id}' to project '#{project.identifier}': #{e.message}", level: :warn)
        false
      end

      # Public: Generates a resume authentication token for a Redmine user in Rocket.Chat
      # Also ensures the user is a member of the project's Rocket.Chat group if a project is passed.
      def create_user_login_token(user, project: nil)
        return nil if user.nil? || user.anonymous?
        return nil if plugin_settings['auto_login_users'] == 'false'

        rc_user_id = ensure_rocket_chat_user(user)
        if project
          channel_name = channel_name_for(project)
          room_id = get_or_create_project_room_id(project)
          if room_id && (user.allowed_to?(:access_chat, project) || project.users.include?(user) || user.admin?) && rc_user_id.present?
            current_members = fetch_channel_members(room_id)
            manage_channel_user(:add, user.login, channel_name, room_id: room_id) unless current_members.include?(user.login)
          end
        end

        params = rc_user_id ? { 'userId' => rc_user_id } : { 'username' => user.login }
        secret = plugin_settings['rocket_chat_token_secret'].presence
        if secret
          params['secret'] = secret
          response = execute_request('users.createToken', params: params)
          response&.dig('data', 'authToken')
        else
          nil
        end
      rescue StandardError => e
        log("Failed to create login token for '#{user&.login}': #{e.message}", level: :error)
        nil
      end

      # Public: Sends a message to a Rocket.Chat room (optionally inside a thread via `tmid`)
      def send_chat_message(room_id, text, tmid: nil, alias_name: nil)
        return nil if room_id.blank? || text.blank?

        message_payload = {
          'rid' => room_id,
          'msg' => text
        }
        message_payload['tmid'] = tmid if tmid.present?
        message_payload['alias'] = alias_name if alias_name.present?

        response = execute_request(
          'chat.sendMessage',
          params: { 'message' => message_payload }
        )
        response&.dig('message')
      end

      # Public: Fetches a single Rocket.Chat message by its ID
      def get_message(msg_id)
        return nil if msg_id.blank?

        response = execute_request(
          "chat.getMessage?msgId=#{URI.encode_www_form_component(msg_id)}",
          http_method: Net::HTTP::Get
        )
        response&.dig('message')
      end

      # Public: Ensures a root thread message exists in the project's Rocket.Chat room for the given Issue.
      # Stores the message `_id` in `issue.rocketchat_thread_id` and returns the message hash.
      def ensure_issue_thread(issue)
        return nil unless issue&.project

        room_id = get_or_create_project_room_id(issue.project)
        return nil unless room_id

        if issue.respond_to?(:rocketchat_thread_id) && issue.rocketchat_thread_id.present?
          existing_msg = get_message(issue.rocketchat_thread_id)
          return existing_msg if existing_msg.present?
        end

        issue_url = "#{redmine_base_url}/issues/#{issue.id}"
        tracker_name = issue.tracker&.name || 'Issue'
        status_name = issue.status&.name || ''
        priority_name = issue.priority&.name || ''
        assigned_name = issue.assigned_to&.name || '-'
        author_name = issue.author&.name || '-'

        header = "🎫 **[##{issue.id}: #{issue.subject}](#{issue_url})**"
        meta = "_#{tracker_name} | Status: **#{status_name}** | Priority: #{priority_name} | Author: #{author_name} | Assigned: #{assigned_name}_"
        desc = issue.description.to_s.strip
        desc_preview = desc.present? ? "\n> #{desc.truncate(280).gsub(/\r?\n/, "\n> ")}" : ''

        msg_text = "#{header}\n#{meta}#{desc_preview}"
        msg = send_chat_message(room_id, msg_text)

        if msg && msg['_id'].present?
          issue.update_column(:rocketchat_thread_id, msg['_id']) if issue.respond_to?(:rocketchat_thread_id)
          msg
        else
          nil
        end
      end

      # Public: Posts a Redmine issue journal update (notes / status change) as a reply inside the issue's thread
      def post_issue_journal_to_thread(issue, journal)
        return nil unless issue && journal && issue.respond_to?(:rocketchat_thread_id) && issue.rocketchat_thread_id.present?
        return nil if issue.respond_to?(:is_private?) && issue.is_private?
        return nil if journal.respond_to?(:private_notes?) && journal.private_notes?

        room_id = get_or_create_project_room_id(issue.project)
        return nil unless room_id

        lines = []
        user_name = journal.user&.name || 'Redmine'
        issue_url = "#{redmine_base_url}/issues/#{issue.id}#change-#{journal.id}"

        lines << "🔄 **Update by #{user_name}** ([##{issue.id}](#{issue_url})):"
        if journal.details.any?
          lines << "Status: **#{issue.status&.name}** | Assigned: **#{issue.assigned_to&.name || '-'}** | Done: #{issue.done_ratio}%"
        end
        if journal.notes.present? && !(journal.respond_to?(:private_notes?) && journal.private_notes?)
          lines << "> #{journal.notes.to_s.strip.truncate(400).gsub(/\r?\n/, "\n> ")}"
        end

        return nil if lines.size <= 1 && journal.notes.blank? && journal.details.empty?

        send_chat_message(room_id, lines.join("\n"), tmid: issue.rocketchat_thread_id)
      end

      # Public: Returns the configured Redmine base URL
      def redmine_base_url
        url = plugin_settings['redmine_host_url'].presence
        return url.chomp('/') if url.present?

        protocol = Setting.protocol.presence || 'http'
        host = Setting.host_name.to_s.chomp('/')
        "#{protocol}://#{host}"
      end

      private

      def resolve_user(user_or_username)
        if user_or_username.is_a?(User)
          [user_or_username, user_or_username.login]
        else
          username = user_or_username.to_s
          [User.find_by(login: username), username]
        end
      end

      # Ensures that the Rocket.Chat settings are initialized
      def initialize_settings!
        @base_url = build_base_url
        @token = fetch_setting('rocket_chat_token')
        @user_id = fetch_setting('rocket_chat_user_id')

        validate_settings!
      end

      # Ensures that a channel exists, creating it if necessary, and returns room_id
      def ensure_channel_exists(channel_name, project)
        room_id = get_channel_id(channel_name)
        if room_id.present?
          log("Channel '#{channel_name}' already exists (#{room_id})", context: project.identifier)
          room_id
        else
          log("Channel '#{channel_name}' does not exist. Creating now...", context: project.identifier)
          create_rocket_chat_channel(project)
        end
      end

      # Synchronizes Redmine project members with the Rocket.Chat channel
      def sync_members_to_channel(project, channel_name, room_id: nil)
        log("Synchronizing members for channel '#{channel_name}'", context: project.identifier)
        room_id ||= get_channel_id(channel_name)
        return log("Failed to retrieve room ID for channel '#{channel_name}'", level: :error, context: project.identifier) unless room_id

        current_members = fetch_channel_members(room_id)
        project_users = project.members
                               .map(&:user)
                               .compact
                               .reject(&:anonymous?)
                               .select { |u| u.allowed_to?(:access_chat, project) }
        admin_logins = User.active.where(admin: true).pluck(:login)
        project_logins = project_users.map(&:login)

        (current_members - project_logins - admin_logins - ['redmine_bot']).each do |member_login|
          log("Removing user '#{member_login}' from channel '#{channel_name}'", context: project.identifier)
          remove_member_from_channel(member_login, channel_name, room_id: room_id)
        end

        project_users.each do |user|
          next if current_members.include?(user.login)

          log("Adding user '#{user.login}' to channel '#{channel_name}'", context: project.identifier)
          add_member_to_channel(user, channel_name, room_id: room_id)
        end
      end

      # Checks if a channel exists in Rocket.Chat
      def channel_exists?(channel_name)
        get_channel_id(channel_name).present?
      end

      # Fetches the members of a Rocket.Chat channel
      def fetch_channel_members(room_id)
        response = execute_request(
          "groups.members?roomId=#{URI.encode_www_form_component(room_id)}",
          http_method: Net::HTTP::Get
        )
        response&.dig('members')&.map { |member| member['username'] } || []
      end

      # Validates that all required settings are present
      def validate_settings!
        if [@base_url, @token, @user_id].any?(&:blank?)
          log_and_raise(I18n.t('rocketchat.helper.errors.missing_configuration'))
        end
      end

      # Builds the base URL for Rocket.Chat API requests
      def build_base_url
        base = plugin_settings['rocket_chat_url_internal'].presence || plugin_settings['rocket_chat_url']
        "#{base.to_s.chomp('/')}/api/v1"
      end

      # Fetches a specific setting and logs an error if it's missing
      def fetch_setting(key)
        plugin_settings[key].tap do |value|
          log("Missing configuration for #{key}", level: :error) if value.blank?
        end
      end

      # Executes an HTTP request to Rocket.Chat
      def execute_request(endpoint, http_method: Net::HTTP::Post, params: {}, success_action: nil)
        initialize_settings!
        uri = URI("#{@base_url}/#{endpoint}")
        req = build_request(uri, http_method, params)

        begin
          response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 5, read_timeout: 10) do |http|
            http.request(req)
          end

          handle_response(response, success_action)
        rescue StandardError => e
          log("Exception during HTTP request (#{endpoint}): #{e.message}", level: :error)
          nil
        end
      end

      # Builds an HTTP request with JSON payload and authentication headers
      def build_request(uri, http_method, params)
        req = http_method.new(uri)
        req['X-Auth-Token'] = token
        req['X-User-Id'] = user_id
        req['Accept'] = 'application/json'
        unless params.empty?
          req['Content-Type'] = 'application/json'
          req.body = params.to_json
        end
        req
      end

      # Handles the HTTP response from Rocket.Chat
      def handle_response(response, success_action)
        case response
        when Net::HTTPSuccess
          body = JSON.parse(response.body)
          success_action&.call(body) if body['success'] || body['status'] == 'success'
          body
        else
          log_error_response(response)
          nil
        end
      end

      # Logs an error response from Rocket.Chat
      def log_error_response(response)
        parsed = JSON.parse(response.body) rescue {}
        error_message = parsed['error'] || parsed['message'] || 'Unknown error'
        log("HTTP request failed. Status: #{response.code}, Error: #{error_message}", level: :error)
      end

      # Logs and raises a critical error
      def log_and_raise(message)
        log(message, level: :error)
        raise message
      end

      # Logs messages with contextual information
      def log(message, level: :info, context: nil)
        prefix = context ? "Rocket.Chat [#{context}]" : 'Rocket.Chat'
        Rails.logger.public_send(level, "#{prefix}: #{message}")
      end

      # Validates the channel name before proceeding
      def with_valid_channel(channel_name)
        if valid_channel_name?(channel_name)
          yield
        else
          log("Invalid channel name '#{channel_name}'", level: :error)
        end
      end

      # Checks if a channel name is valid
      def valid_channel_name?(channel_name)
        /^[a-zA-Z0-9_\-]+$/.match?(channel_name) && channel_name.length <= 50
      end
    end
  end
end
