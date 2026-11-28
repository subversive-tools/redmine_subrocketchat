# app/controllers/rocket_chat_controller.rb
# Controller for displaying and interacting with Rocket.Chat channels, issue threads, and the Rocket.Chat 8.x compatibility proxy.

class RocketChatController < ApplicationController
  before_action :require_admin, only: [:admin_setup]
  before_action :ensure_legacy_settings_migrated
  before_action :find_project, :authorize, except: [:admin_setup]

  # Strict allowlist of Rocket.Chat REST API endpoints that EmbeddedChat may call through the proxy.
  # Any other endpoint (e.g. users.list, users.create, users.setActiveStatus, groups.listAll, settings/*, etc.) is rejected with 403 Forbidden.
  ALLOWED_PROXY_GET_ENDPOINTS = %w[
    api/v1/me
    api/v1/rooms.info
    api/v1/groups.info
    api/v1/groups.messages
    api/v1/groups.members
    api/v1/groups.roles
    api/v1/groups.files
    api/v1/channels.images
    api/v1/chat.getThreadMessages
    api/v1/chat.getStarredMessages
    api/v1/chat.getPinnedMessages
    api/v1/chat.getMentionedMessages
    api/v1/chat.search
    api/v1/chat.syncMessages
    api/v1/permissions.listAll
    api/v1/roles.getUsersInRole
    api/v1/commands.list
    api/v1/users.info
    api/v1/users.getStatus
    api/v1/users.getUsernameSuggestion
    api/v1/settings/Message_MaxAllowedSize
  ].freeze

  ALLOWED_PROXY_POST_ENDPOINTS = %w[
    api/v1/login
    api/v1/logout
    api/v1/chat.sendMessage
    api/v1/chat.delete
    api/v1/chat.update
    api/v1/chat.react
    api/v1/chat.starMessage
    api/v1/chat.unStarMessage
    api/v1/chat.pinMessage
    api/v1/chat.unPinMessage
    api/v1/chat.reportMessage
    api/v1/commands.run
    api/v1/findOrCreateInvite
  ].freeze

  # Room-scoped endpoints where `roomId` / `rid` MUST equal the current Redmine project's Rocket.Chat room ID.
  ROOM_SCOPED_GET_ENDPOINTS = %w[
    api/v1/rooms.info
    api/v1/groups.info
    api/v1/groups.messages
    api/v1/groups.members
    api/v1/groups.roles
    api/v1/groups.files
    api/v1/channels.images
    api/v1/chat.getStarredMessages
    api/v1/chat.getPinnedMessages
    api/v1/chat.getMentionedMessages
    api/v1/chat.search
    api/v1/chat.syncMessages
  ].freeze

  ROOM_SCOPED_POST_ENDPOINTS = %w[
    api/v1/chat.sendMessage
    api/v1/chat.delete
    api/v1/chat.update
    api/v1/commands.run
    api/v1/findOrCreateInvite
  ].freeze

  # Endpoints operating on a single `messageId` where we verify the message belongs to the current project's room.
  MESSAGE_SCOPED_POST_ENDPOINTS = %w[
    api/v1/chat.react
    api/v1/chat.starMessage
    api/v1/chat.unStarMessage
    api/v1/chat.pinMessage
    api/v1/chat.unPinMessage
    api/v1/chat.reportMessage
  ].freeze

  # Safe raster image & audio/video MIME types allowed to be displayed inline by the media proxy.
  # Potentially active content (text/html, image/svg+xml, application/javascript, text/xml, etc.) is forced to `attachment` + `application/octet-stream`.
  SAFE_INLINE_MEDIA_TYPES = %w[
    image/png
    image/jpeg
    image/gif
    image/webp
    image/avif
    image/bmp
    audio/mpeg
    audio/ogg
    audio/wav
    audio/webm
    audio/mp4
    video/mp4
    video/webm
    video/ogg
  ].freeze

  def show
    # Renders app/views/rocket_chat/show.html.erb
  end

  # POST /rocket_chat/admin_setup
  # 1-Click Setup Wizard & Connection Tester for the plugin settings page (Admin only)
  def admin_setup
    op = params[:operation].to_s
    rc_url = params[:rocket_chat_url].to_s.strip.chomp('/')
    rc_internal = params[:rocket_chat_url_internal].to_s.strip.chomp('/')
    base_url = (rc_internal.presence || rc_url)

    if base_url.blank?
      return render json: { success: false, error: I18n.t('rocketchat.settings.wizard.missing_url', default: 'Please enter the Rocket.Chat URL first.') }, status: :unprocessable_entity
    end

    case op
    when 'connect_login'
      username = params[:username].to_s.strip
      password = params[:password].to_s
      if username.blank? || password.blank?
        return render json: { success: false, error: I18n.t('rocketchat.settings.wizard.missing_credentials', default: 'Please enter both username and password.') }, status: :unprocessable_entity
      end

      login_res = rc_raw_request("#{base_url}/api/v1/login", method: :post, payload: { user: username, password: password })
      unless login_res[:ok] && login_res[:json].dig('data', 'authToken').present?
        err_msg = login_res[:json]['error'] || login_res[:json]['message'] || login_res[:error] || 'Login failed'
        return render json: { success: false, error: err_msg }, status: :unprocessable_entity
      end

      user_id = login_res[:json].dig('data', 'userId')
      temp_token = login_res[:json].dig('data', 'authToken')
      final_token = temp_token
      token_type = 'login_token'

      # Try to create or regenerate a non-expiring Personal Access Token (`redmine_subrocketchat`) if the user has permission
      pat_name = 'redmine_subrocketchat'
      pat_res = rc_raw_request(
        "#{base_url}/api/v1/users.generatePersonalAccessToken",
        method: :post,
        headers: { 'X-User-Id' => user_id, 'X-Auth-Token' => temp_token },
        payload: { tokenName: pat_name, bypassTwoFactor: true }
      )
      if !pat_res[:ok] && pat_res[:json]['errorType'] == 'error-token-already-exists'
        pat_res = rc_raw_request(
          "#{base_url}/api/v1/users.regeneratePersonalAccessToken",
          method: :post,
          headers: { 'X-User-Id' => user_id, 'X-Auth-Token' => temp_token },
          payload: { tokenName: pat_name }
        )
      end
      if pat_res[:ok] && pat_res[:json]['token'].present?
        final_token = pat_res[:json]['token']
        token_type = 'personal_access_token'
      end

      # Persist immediately into Setting.plugin_redmine_subrocketchat so the admin does not even lose it if they forget to click Save
      current_settings = (Setting.plugin_redmine_subrocketchat || {}).dup
      current_settings['rocket_chat_url'] = rc_url if rc_url.present?
      current_settings['rocket_chat_url_internal'] = rc_internal
      current_settings['rocket_chat_user_id'] = user_id
      current_settings['rocket_chat_token'] = final_token
      Setting.plugin_redmine_subrocketchat = current_settings

      me_info = login_res[:json].dig('data', 'me') || {}
      render json: {
        success: true,
        user_id: user_id,
        token: final_token,
        token_type: token_type,
        username: me_info['username'] || username,
        name: me_info['name'] || username,
        roles: me_info['roles'] || []
      }

    when 'test_connection'
      user_id = params[:rocket_chat_user_id].to_s.strip.presence || Setting.plugin_redmine_subrocketchat['rocket_chat_user_id']
      token = params[:rocket_chat_token].to_s.strip.presence || Setting.plugin_redmine_subrocketchat['rocket_chat_token']

      if user_id.blank? || token.blank?
        return render json: { success: false, error: I18n.t('rocketchat.settings.wizard.missing_token', default: 'User ID or API Token is missing. Use the 1-Click Login above or enter them manually.') }, status: :unprocessable_entity
      end

      me_res = rc_raw_request(
        "#{base_url}/api/v1/me",
        method: :get,
        headers: { 'X-User-Id' => user_id, 'X-Auth-Token' => token }
      )
      unless me_res[:ok] && me_res[:json]['_id'].present?
        err_msg = me_res[:json]['error'] || me_res[:json]['message'] || me_res[:error] || 'Authentication failed'
        return render json: { success: false, error: err_msg }, status: :unprocessable_entity
      end

      info_res = rc_raw_request(
        "#{base_url}/api/info",
        method: :get,
        headers: { 'X-User-Id' => user_id, 'X-Auth-Token' => token }
      )
      rc_version = info_res[:json].dig('info', 'version') || info_res[:json]['version'] || 'OK'

      render json: {
        success: true,
        username: me_res[:json]['username'],
        name: me_res[:json]['name'],
        roles: me_res[:json]['roles'] || [],
        rc_version: rc_version
      }

    when 'apply_quick_setup'
      role_ids = Array(params[:role_ids]).map(&:to_i).reject(&:zero?)
      Role.givable.find_each do |role|
        if role_ids.include?(role.id)
          role.add_permission!(:access_chat) unless role.allowed_to?(:access_chat)
        else
          role.remove_permission!(:access_chat) if role.allowed_to?(:access_chat)
        end
      end

      if params[:enable_default_module].to_s == 'true'
        mods = Array(Setting.default_projects_modules).map(&:to_s)
        Setting.default_projects_modules = (mods | ['rocket_chat'])
      end

      synced_projects = 0
      if params[:enable_all_projects].to_s == 'true'
        Project.active.find_each do |proj|
          unless proj.module_enabled?(:rocket_chat)
            proj.enabled_module_names = (proj.enabled_module_names | ['rocket_chat'])
          end
          RedmineSubrocketchat::RocketChatHelper.sync_channel_and_members(proj)
          synced_projects += 1
        rescue StandardError => e
          Rails.logger.warn("Subrocketchat quick setup sync warning for #{proj.identifier}: #{e.message}")
        end
      elsif params[:sync_active_projects].to_s == 'true'
        Project.active.find_each do |proj|
          next unless proj.module_enabled?(:rocket_chat)

          RedmineSubrocketchat::RocketChatHelper.sync_channel_and_members(proj)
          synced_projects += 1
        rescue StandardError => e
          Rails.logger.warn("Subrocketchat quick setup sync warning for #{proj.identifier}: #{e.message}")
        end
      end

      render json: {
        success: true,
        roles_updated: role_ids.size,
        synced_projects: synced_projects
      }
    else
      render json: { success: false, error: "Unknown operation: #{op}" }, status: :bad_request
    end
  end

  # GET /projects/:project_id/rocket_chat/session
  # Returns JSON configuration for EmbeddedChat (host, roomId, channelName, authToken, optional issue thread info)
  def session_config
    unless RedmineSubrocketchat::RocketChatHelper.configured?
      return render json: {
        configured: false,
        settings_url: User.current.admin? ? '/settings/plugin/redmine_subrocketchat' : nil
      }
    end

    channel_name = RedmineSubrocketchat::RocketChatHelper.channel_name_for(@project)
    room_id = RedmineSubrocketchat::RocketChatHelper.get_or_create_project_room_id(@project)
    auth_token = RedmineSubrocketchat::RocketChatHelper.create_user_login_token(User.current, project: @project)

    issue_data = nil
    if params[:issue_id].present?
      issue = Issue.visible.where(project_id: @project.self_and_descendants.select(:id)).find_by(id: params[:issue_id])
      if issue
        thread_id = issue.respond_to?(:rocketchat_thread_id) ? issue.rocketchat_thread_id : nil
        thread_msg = thread_id.present? ? RedmineSubrocketchat::RocketChatHelper.get_message(thread_id) : nil

        if thread_msg.nil? &&
           Setting.plugin_redmine_subrocketchat['auto_create_issue_threads'] == 'true' &&
           !(issue.respond_to?(:is_private?) && issue.is_private?)
          thread_msg = RedmineSubrocketchat::RocketChatHelper.ensure_issue_thread(issue)
        end

        issue_data = {
          id: issue.id,
          subject: issue.subject,
          tracker: issue.tracker&.name,
          status: issue.status&.name,
          url: "#{RedmineSubrocketchat::RocketChatHelper.redmine_base_url}/issues/#{issue.id}",
          thread_id: thread_msg ? thread_msg['_id'] : thread_id,
          thread_message: thread_msg
        }
      end
    end

    render json: {
      host: Setting.plugin_redmine_subrocketchat['rocket_chat_url'].to_s.chomp('/'),
      room_id: room_id,
      channel_name: channel_name,
      auth_token: auth_token,
      user: {
        id: User.current.id,
        login: User.current.login,
        name: User.current.name
      },
      redmine_base_url: RedmineSubrocketchat::RocketChatHelper.redmine_base_url,
      issue: issue_data
    }
  end

  # GET /projects/:project_id/rocket_chat/issues?q=...
  # Searches project issues for the `#1234` live autocomplete dropdown in the chat input
  def issues
    query = params[:q].to_s.strip
    scope = Issue.visible.where(project_id: @project.self_and_descendants.select(:id))

    if query.present?
      if query =~ /\A#?(\d+)\z/
        num = Regexp.last_match(1)
        scope = scope.where('CAST(issues.id AS CHAR) LIKE ? OR LOWER(issues.subject) LIKE ?', "#{num}%", "%#{query.downcase}%")
      else
        clean_q = query.sub(/\A#/, '').downcase
        scope = scope.where('CAST(issues.id AS CHAR) LIKE ? OR LOWER(issues.subject) LIKE ?', "%#{clean_q}%", "%#{clean_q}%")
      end
    end

    issues_list = scope.includes(:tracker, :status, :assigned_to)
                       .order(updated_on: :desc, id: :desc)
                       .limit(15)
                       .map do |iss|
      {
        id: iss.id,
        subject: iss.subject,
        tracker: iss.tracker&.name,
        status: iss.status&.name,
        is_closed: iss.closed?,
        assigned_to: iss.assigned_to&.name,
        thread_id: iss.respond_to?(:rocketchat_thread_id) ? iss.rocketchat_thread_id : nil,
        url: "#{RedmineSubrocketchat::RocketChatHelper.redmine_base_url}/issues/#{iss.id}"
      }
    end

    render json: { issues: issues_list }
  end

  # POST /projects/:project_id/rocket_chat/issue_thread/:issue_id
  # Ensures a Rocket.Chat thread exists for the given issue and returns its message object so EmbeddedChat can open it directly
  def issue_thread
    issue = Issue.visible.where(project_id: @project.self_and_descendants.select(:id)).find(params[:issue_id])
    msg = RedmineSubrocketchat::RocketChatHelper.ensure_issue_thread(issue)

    if msg
      render json: {
        success: true,
        thread_id: msg['_id'],
        thread_message: msg,
        issue: {
          id: issue.id,
          subject: issue.subject,
          tracker: issue.tracker&.name,
          status: issue.status&.name
        }
      }
    else
      render json: {
        success: false,
        error: I18n.t('rocketchat.thread.create_error', default: 'Could not create ticket thread in Rocket.Chat.')
      }, status: :unprocessable_entity
    end
  end

  # Hardened proxy for EmbeddedChat REST & media calls:
  # - Protected by Rails CSRF verification (our fetch wrapper automatically attaches Redmine's `X-CSRF-Token`).
  # - NEVER falls back to the bot/admin token for API calls.
  # - Enforces a strict method & endpoint allowlist.
  # - Restricts all room-scoped and message-scoped endpoints (and media downloads) to the current Redmine project's Rocket.Chat room (`rm_<project_identifier>`).
  # - Verifies caller identity AND matching Redmine user identity before auto-inviting on `login` or `rooms.info`.
  def proxy
    rc_base = (Setting.plugin_redmine_subrocketchat['rocket_chat_url_internal'].presence ||
               Setting.plugin_redmine_subrocketchat['rocket_chat_url']).to_s.chomp('/')
    rc_path = params[:rc_path].to_s

    # Block path traversal or unexpected characters
    if rc_path.include?('..') || rc_path.start_with?('/')
      return render json: { status: 'error', error: 'Invalid proxy path' }, status: :forbidden
    end

    # 1. Media downloads: `GET /file-upload/:file_id/:filename` or `GET /ufs/:store/:file_id/:filename`
    if request.method_symbol == :get && rc_path =~ /\A(?:file-upload\/([^\/]+)\/(.+)|ufs\/[^\/]+\/([^\/]+)\/(.+))\z/
      file_id = Regexp.last_match(1) || Regexp.last_match(3)
      raw_filename = Regexp.last_match(2) || Regexp.last_match(4)
      return proxy_project_media_download(rc_base, rc_path, file_id, raw_filename)
    end

    # 2. All Redmine project channels are private groups (`groups.*`).
    rc_path = rc_path.sub(/\Aapi\/v1\/channels\.(messages|members|roles|files|info)\z/, 'api/v1/groups.\1')

    # 3. Stub `GET api/v1/settings/Message_MaxAllowedSize` (harmless static value)
    if request.method_symbol == :get && rc_path == 'api/v1/settings/Message_MaxAllowedSize'
      return render json: { _id: 'Message_MaxAllowedSize', value: 5000, success: true }, status: :ok
    end

    # 4. Unauthenticated login endpoint: `POST api/v1/login`
    if request.method_symbol == :post && rc_path == 'api/v1/login'
      return proxy_login_and_ensure_room_member(rc_base)
    end

    # 5. Require explicit user authentication headers (`X-Auth-Token` and `X-User-Id`) for ALL other API requests.
    # NEVER fall back to the bot/admin token!
    auth_token = request.headers['X-Auth-Token'].to_s.strip
    rc_user_id = request.headers['X-User-Id'].to_s.strip
    if auth_token.blank? || rc_user_id.blank?
      return render json: { status: 'error', error: 'Authentication required (missing X-Auth-Token or X-User-Id)' }, status: :unauthorized
    end

    # 6. Upload endpoint: `POST api/v1/rooms.upload/:rid` (scoped to project room!)
    if request.method_symbol == :post && rc_path =~ /\Aapi\/v1\/rooms\.upload\/([^\/\?]+)\z/
      target_rid = Regexp.last_match(1)
      unless valid_project_room_id?(target_rid)
        return render json: { status: 'error', error: 'Access denied: room does not belong to this project' }, status: :forbidden
      end
      return proxy_rooms_upload_v8(rc_base, target_rid, auth_token, rc_user_id)
    end

    # 7. Enforce strict method & endpoint allowlist
    method_sym = request.method_symbol
    allowed = case method_sym
              when :get
                ALLOWED_PROXY_GET_ENDPOINTS.include?(rc_path)
              when :post
                ALLOWED_PROXY_POST_ENDPOINTS.include?(rc_path)
              else
                false
              end

    unless allowed
      return render json: { status: 'error', error: "Endpoint not allowed by proxy: #{method_sym.to_s.upcase} #{rc_path}" }, status: :forbidden
    end

    # 8. Enforce project room boundary on all room-scoped and message-scoped endpoints
    unless enforce_project_room_scope!(method_sym, rc_path, rc_base, auth_token, rc_user_id)
      return render json: { status: 'error', error: 'Access denied: request targets a room or message outside this project' }, status: :forbidden
    end

    # 9. Special Rocket.Chat 8.x compatibility handlers (using caller's own token!)
    if method_sym == :get && rc_path == 'api/v1/rooms.info' && params[:roomId].present?
      return proxy_rooms_info_with_auto_invite(rc_base, auth_token, rc_user_id)
    end

    if method_sym == :get && rc_path == 'api/v1/chat.getThreadMessages'
      return proxy_thread_messages_v8(rc_base, params[:tmid].to_s, auth_token, rc_user_id)
    end

    if method_sym == :get && rc_path == 'api/v1/groups.messages' && params[:query].present?
      return proxy_messages_with_query_v8(rc_base, rc_path, auth_token, rc_user_id)
    end

    if method_sym == :get && (rc_path == 'api/v1/channels.images' || rc_path == 'api/v1/groups.files')
      return proxy_room_files_v8(rc_base, auth_token, rc_user_id, images_only: rc_path == 'api/v1/channels.images')
    end

    query_str = request.query_string.presence
    encoded_path = rc_path.split('/').map { |seg| ERB::Util.url_encode(seg) }.join('/')
    target_url = "#{rc_base}/#{encoded_path}"
    target_url += "?#{query_str}" if query_str

    uri = URI(target_url)
    method_class = method_sym == :post ? Net::HTTP::Post : Net::HTTP::Get

    req = method_class.new(uri)
    req['Content-Type'] = request.content_type if request.content_type.present?
    req['Accept'] = request.headers['Accept'] || 'application/json'
    req['X-Auth-Token'] = auth_token
    req['X-User-Id'] = rc_user_id

    if method_sym == :post
      body_content = request.raw_post
      req.body = body_content if body_content.present?
    end

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 10, read_timeout: 30) do |http|
      http.request(req)
    end

    resp_content_type = response['content-type'] || 'application/json'
    resp_body = response.body.to_s
    if resp_body.strip.empty? && resp_content_type.include?('json')
      resp_body = '{"status":"success","success":true}'
    end

    render plain: resp_body, status: response.code.to_i, content_type: resp_content_type
  rescue StandardError => e
    Rails.logger.error("Rocket.Chat Proxy Error (#{params[:rc_path]}): #{e.message}")
    render json: { status: 'error', error: e.message }, status: :bad_gateway
  end

  private

  # Returns the Rocket.Chat room ID for the current Redmine project (`rm_<project_identifier>`).
  def project_room_id
    @project_room_id ||= RedmineSubrocketchat::RocketChatHelper.get_or_create_project_room_id(@project)
  end

  def valid_project_room_id?(candidate_rid)
    expected = project_room_id
    expected.present? && candidate_rid.to_s == expected.to_s
  end

  # Verifies that any room-scoped GET or POST request (or messageId-scoped POST request) exclusively targets `@project`'s Rocket.Chat room.
  def enforce_project_room_scope!(method_sym, rc_path, rc_base, auth_token, rc_user_id)
    if method_sym == :get && ROOM_SCOPED_GET_ENDPOINTS.include?(rc_path)
      expected_rid = project_room_id
      return false if expected_rid.blank?

      req_rid = params[:roomId].presence || params[:rid].presence
      if req_rid.present?
        return req_rid.to_s == expected_rid.to_s
      elsif params[:roomName].present?
        return params[:roomName].to_s == RedmineSubrocketchat::RocketChatHelper.channel_name_for(@project)
      else
        return false
      end
    elsif method_sym == :post && ROOM_SCOPED_POST_ENDPOINTS.include?(rc_path)
      expected_rid = project_room_id
      return false if expected_rid.blank?

      parsed_body = JSON.parse(request.raw_post.to_s) rescue {}
      req_rid = case rc_path
                when 'api/v1/chat.sendMessage'
                  parsed_body.dig('message', 'rid') || parsed_body['rid'] || parsed_body['roomId']
                else
                  parsed_body['roomId'] || parsed_body['rid']
                end
      return req_rid.present? && req_rid.to_s == expected_rid.to_s
    elsif method_sym == :post && MESSAGE_SCOPED_POST_ENDPOINTS.include?(rc_path)
      expected_rid = project_room_id
      return false if expected_rid.blank?

      parsed_body = JSON.parse(request.raw_post.to_s) rescue {}
      msg_id = parsed_body['messageId'].presence || parsed_body['msgId'].presence
      return false if msg_id.blank?

      return message_belongs_to_project_room?(rc_base, msg_id, expected_rid, auth_token, rc_user_id)
    end

    true
  end

  # Verifies via `GET /api/v1/chat.getMessage` that a target `messageId` belongs to the current project's Rocket.Chat room.
  def message_belongs_to_project_room?(rc_base, msg_id, expected_rid, auth_token, rc_user_id)
    res = rc_raw_request(
      "#{rc_base}/api/v1/chat.getMessage?msgId=#{URI.encode_www_form_component(msg_id.to_s)}",
      method: :get,
      headers: { 'X-Auth-Token' => auth_token, 'X-User-Id' => rc_user_id }
    )
    return false unless res[:ok]

    msg_rid = res[:json].dig('message', 'rid').to_s
    msg_rid.present? && msg_rid == expected_rid.to_s
  end

  # Verifies that the authenticated Rocket.Chat user (`me_hash`) matches the currently logged-in Redmine user (`User.current`)
  # by login/username or email address (or that `User.current` is a Redmine administrator).
  # This prevents a project member from logging into EmbeddedChat with an external colleague's Rocket.Chat credentials
  # to have the bot auto-invite that external Rocket.Chat account into the private project group.
  def rc_user_matches_current_redmine_user?(me_hash)
    return false unless User.current&.logged?
    return true if User.current.admin?
    return false unless me_hash.is_a?(Hash)

    rc_username = me_hash['username'].to_s.strip
    return true if rc_username.present? && rc_username.casecmp?(User.current.login.to_s.strip)

    redmine_emails = if User.current.respond_to?(:mails)
                       Array(User.current.mails).map { |e| e.to_s.strip.downcase }.reject(&:blank?)
                     else
                       [User.current.mail.to_s.strip.downcase].reject(&:blank?)
                     end

    rc_emails = Array(me_hash['emails']).map { |e| e.is_a?(Hash) ? e['address'].to_s.strip.downcase : e.to_s.strip.downcase }.reject(&:blank?)
    (redmine_emails & rc_emails).any?
  end

  # Securely proxies media downloads (`/file-upload/:file_id/:filename` or `/ufs/:store/:file_id/:filename`) with XSS protection:
  # - Verifies that `file_id` belongs to the current project's Rocket.Chat group (`groups.files`).
  # - Enforces `X-Content-Type-Options: nosniff` and a strict sandboxed `Content-Security-Policy`.
  # - Only allows safe raster image, audio, and video MIME types to be displayed inline; any potentially active content
  #   (such as `text/html`, `image/svg+xml`, `application/javascript`, `text/xml`, etc.) is forced to `Content-Disposition: attachment`
  #   with `Content-Type: application/octet-stream` so it can never execute scripts under Redmine's origin.
  def proxy_project_media_download(rc_base, rc_path, file_id, raw_filename = nil)
    expected_rid = project_room_id
    if expected_rid.blank? || file_id.blank? || !project_room_has_file?(rc_base, expected_rid, file_id)
      return render json: { status: 'error', error: 'File not found in this project room' }, status: :forbidden
    end

    bot_token = Setting.plugin_redmine_subrocketchat['rocket_chat_token'].to_s
    bot_uid = Setting.plugin_redmine_subrocketchat['rocket_chat_user_id'].to_s
    if bot_token.blank? || bot_uid.blank?
      return render json: { status: 'error', error: 'Rocket.Chat bot credentials not configured' }, status: :service_unavailable
    end

    query_str = request.query_string.presence
    encoded_path = rc_path.split('/').map { |seg| ERB::Util.url_encode(seg) }.join('/')
    target_url = "#{rc_base}/#{encoded_path}"
    target_url += "?#{query_str}" if query_str

    uri = URI(target_url)
    req = Net::HTTP::Get.new(uri)
    req['X-Auth-Token'] = bot_token
    req['X-User-Id'] = bot_uid
    req['Cookie'] = "rc_uid=#{bot_uid}; rc_token=#{bot_token}"

    rc_res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 10, read_timeout: 30) do |http|
      http.request(req)
    end

    upstream_type = rc_res['content-type'].to_s.split(';').first.to_s.strip.downcase
    safe_filename = URI.decode_www_form_component(raw_filename.to_s).gsub(/["\\\r\n]/, '_').presence || 'download'

    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['Content-Security-Policy'] = "default-src 'none'; img-src 'self' data:; media-src 'self'; style-src 'unsafe-inline'; sandbox"

    if SAFE_INLINE_MEDIA_TYPES.include?(upstream_type)
      response.headers['Content-Disposition'] = "inline; filename=\"#{safe_filename}\""
      out_type = upstream_type
    else
      response.headers['Content-Disposition'] = "attachment; filename=\"#{safe_filename}\""
      out_type = 'application/octet-stream'
    end

    render plain: rc_res.body, status: rc_res.code.to_i, content_type: out_type
  end

  # Checks via Rocket.Chat's `groups.files` API (scoped to `room_id` and filtered by `_id`) whether `file_id` belongs to the project room.
  def project_room_has_file?(rc_base, room_id, file_id)
    bot_token = Setting.plugin_redmine_subrocketchat['rocket_chat_token'].to_s
    bot_uid = Setting.plugin_redmine_subrocketchat['rocket_chat_user_id'].to_s
    return false if bot_token.blank? || bot_uid.blank?

    query_json = { _id: file_id.to_s }.to_json
    uri = URI("#{rc_base}/api/v1/groups.files?roomId=#{URI.encode_www_form_component(room_id)}&query=#{URI.encode_www_form_component(query_json)}&count=100")
    req = Net::HTTP::Get.new(uri)
    req['X-Auth-Token'] = bot_token
    req['X-User-Id'] = bot_uid
    req['Accept'] = 'application/json'

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 8, read_timeout: 15) do |http|
      http.request(req)
    end
    return false unless res.is_a?(Net::HTTPSuccess)

    data = JSON.parse(res.body) rescue {}
    files = data['files']
    files.is_a?(Array) && files.any? { |f| f['_id'].to_s == file_id.to_s }
  rescue StandardError
    false
  end

  # Intercepts `POST /api/v1/login` from EmbeddedChat. When the user successfully authenticates,
  # automatically ensures that the authenticated Rocket.Chat user (`data.userId`) is invited to the
  # current project's private Rocket.Chat group ONLY IF the Rocket.Chat account matches `User.current`
  # (by username/email or Redmine admin status).
  def proxy_login_and_ensure_room_member(rc_base)
    uri = URI("#{rc_base}/api/v1/login")
    req = Net::HTTP::Post.new(uri)
    req['Content-Type'] = request.content_type.presence || 'application/json'
    req['Accept'] = 'application/json'
    req.body = request.raw_post

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 10, read_timeout: 20) do |http|
      http.request(req)
    end

    if res.is_a?(Net::HTTPSuccess)
      data = JSON.parse(res.body) rescue {}
      rc_uid = data.dig('data', 'userId')
      me_info = data.dig('data', 'me')
      if rc_uid.present? && @project && rc_user_matches_current_redmine_user?(me_info)
        RedmineSubrocketchat::RocketChatHelper.ensure_rc_user_id_in_project_channel(rc_uid, @project)
      end
    end

    resp_body = res.body.to_s
    resp_body = '{"status":"success","success":true}' if resp_body.strip.empty?
    render plain: resp_body, status: res.code.to_i, content_type: (res['content-type'] || 'application/json')
  end

  # When a user switches to another Redmine project while already logged into EmbeddedChat (via cached token),
  # `GET /api/v1/rooms.info?roomId=...` is called first. If the user is authorized in Redmine (`:access_chat`)
  # but not yet in this project's private Rocket.Chat group (`400 Not Allowed`), we verify their
  # `X-Auth-Token` + `X-User-Id` pair against `GET /api/v1/me` AND verify that the Rocket.Chat account
  # matches `User.current` before inviting them into the room.
  def proxy_rooms_info_with_auto_invite(rc_base, auth_token, rc_user_id)
    room_id = params[:roomId].to_s

    uri = URI("#{rc_base}/api/v1/rooms.info?roomId=#{URI.encode_www_form_component(room_id)}")
    req = Net::HTTP::Get.new(uri)
    req['X-Auth-Token'] = auth_token
    req['X-User-Id'] = rc_user_id
    req['Accept'] = 'application/json'

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 10, read_timeout: 20) do |http|
      http.request(req)
    end

    if !res.is_a?(Net::HTTPSuccess) && @project
      me_res = rc_raw_request(
        "#{rc_base}/api/v1/me",
        method: :get,
        headers: { 'X-Auth-Token' => auth_token, 'X-User-Id' => rc_user_id }
      )
      verified_uid = me_res[:ok] ? me_res[:json]['_id'].to_s : nil
      if verified_uid.present? && verified_uid == rc_user_id && rc_user_matches_current_redmine_user?(me_res[:json])
        RedmineSubrocketchat::RocketChatHelper.ensure_rc_user_id_in_project_channel(verified_uid, @project)
        res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 10, read_timeout: 20) do |http|
          http.request(req)
        end
      end
    end

    render plain: res.body, status: res.code.to_i, content_type: (res['content-type'] || 'application/json')
  end

  # Translates `GET /api/v1/channels.images?roomId=...` and `GET /api/v1/groups.files?roomId=...`
  # using ONLY the caller's own `X-Auth-Token` and `X-User-Id`.
  def proxy_room_files_v8(rc_base, auth_token, rc_user_id, images_only: false)
    room_id = params[:roomId].to_s

    uri = URI("#{rc_base}/api/v1/groups.files?roomId=#{URI.encode_www_form_component(room_id)}&count=100")
    req = Net::HTTP::Get.new(uri)
    req['X-Auth-Token'] = auth_token
    req['X-User-Id'] = rc_user_id
    req['Accept'] = 'application/json'

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 10, read_timeout: 20) do |http|
      http.request(req)
    end

    if res.is_a?(Net::HTTPSuccess)
      data = JSON.parse(res.body) rescue {}
      proxy_prefix = "/projects/#{@project.identifier}/rocket_chat/proxy"
      if data['files'].is_a?(Array)
        files = data['files']
        files = files.select { |f| f['typeGroup'] == 'image' || f['type'].to_s.start_with?('image/') } if images_only
        data['files'] = files.map do |f|
          f['url'] = "#{proxy_prefix}/file-upload/#{f['_id']}/#{URI.encode_www_form_component(f['name'].to_s)}"
          f
        end
      end
      return render json: data, status: :ok
    end

    render plain: res.body, status: res.code.to_i, content_type: (res['content-type'] || 'application/json')
  end

  # Proxies `GET /api/v1/chat.getThreadMessages?tmid=...` and filters returned messages strictly to `@project`'s room ID.
  def proxy_thread_messages_v8(rc_base, tmid_param, auth_token, rc_user_id)
    if tmid_param.blank?
      return render json: { status: 'error', error: 'Missing tmid parameter' }, status: :bad_request
    end

    uri = URI("#{rc_base}/api/v1/chat.getThreadMessages?tmid=#{URI.encode_www_form_component(tmid_param)}")
    req = Net::HTTP::Get.new(uri)
    req['X-Auth-Token'] = auth_token
    req['X-User-Id'] = rc_user_id
    req['Accept'] = 'application/json'

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 10, read_timeout: 20) do |http|
      http.request(req)
    end

    if res.is_a?(Net::HTTPSuccess)
      data = JSON.parse(res.body) rescue {}
      if data['messages'].is_a?(Array)
        expected_rid = project_room_id
        data['messages'] = data['messages']
                             .select { |m| m['rid'].to_s == expected_rid.to_s }
                             .reject { |m| m['_id'] == tmid_param }
                             .sort_by { |m| m['ts'].to_s }
                             .reverse
      end
      return render json: data, status: :ok
    end

    render plain: res.body, status: res.code.to_i, content_type: (res['content-type'] || 'application/json')
  end

  # Rocket.Chat 7.0+ / 8.x disabled arbitrary MongoDB `query={"tmid":...}` parameters on `groups.messages` / `channels.messages` by default.
  # This helper transparently translates thread queries to `chat.getThreadMessages` and filters top-level room messages (`tmid: {$exists: false}`).
  def proxy_messages_with_query_v8(rc_base, rc_path, auth_token, rc_user_id)
    query_hash = JSON.parse(params[:query].to_s) rescue {}
    tmid_param = query_hash['tmid']

    if tmid_param.is_a?(String) && tmid_param.present?
      return proxy_thread_messages_v8(rc_base, tmid_param, auth_token, rc_user_id)
    end

    room_id = params[:roomId].to_s
    uri = URI("#{rc_base}/#{rc_path}?roomId=#{URI.encode_www_form_component(room_id)}&count=100")
    req = Net::HTTP::Get.new(uri)
    req['X-Auth-Token'] = auth_token
    req['X-User-Id'] = rc_user_id
    req['Accept'] = 'application/json'

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 10, read_timeout: 20) do |http|
      http.request(req)
    end

    if res.is_a?(Net::HTTPSuccess) && tmid_param.is_a?(Hash) && tmid_param['$exists'] == false
      data = JSON.parse(res.body) rescue {}
      if data['messages'].is_a?(Array)
        data['messages'] = data['messages'].select { |m| m['tmid'].blank? }
      end
      return render json: data, status: :ok
    end

    render plain: res.body, status: res.code.to_i, content_type: (res['content-type'] || 'application/json')
  end

  # Translates `POST /api/v1/rooms.upload/:rid` (removed in Rocket.Chat 8.0) into:
  # 1) `POST /api/v1/rooms.media/:rid` (multipart file upload)
  # 2) `POST /api/v1/rooms.mediaConfirm/:rid/:fileId` (JSON confirmation with description & tmid)
  def proxy_rooms_upload_v8(rc_base, room_id, auth_token, rc_user_id)
    media_uri = URI("#{rc_base}/api/v1/rooms.media/#{URI.encode_www_form_component(room_id)}")
    media_req = Net::HTTP::Post.new(media_uri)
    media_req['X-Auth-Token'] = auth_token
    media_req['X-User-Id'] = rc_user_id
    media_req['Accept'] = 'application/json'

    uploaded_file = params[:file]
    if uploaded_file.respond_to?(:tempfile)
      boundary = "----RedmineRCBoundary#{SecureRandom.hex(12)}"
      media_req['Content-Type'] = "multipart/form-data; boundary=#{boundary}"
      filename = uploaded_file.original_filename.to_s.gsub('"', '_')
      mime_type = uploaded_file.content_type.presence || 'application/octet-stream'
      file_bytes = File.binread(uploaded_file.tempfile.path)

      body = +''
      body.force_encoding(Encoding::ASCII_8BIT)
      body << "--#{boundary}\r\n"
      body << "Content-Disposition: form-data; name=\"file\"; filename=\"#{filename.dup.force_encoding(Encoding::ASCII_8BIT)}\"\r\n"
      body << "Content-Type: #{mime_type}\r\n\r\n"
      body << file_bytes
      body << "\r\n--#{boundary}--\r\n"
      media_req.body = body
    else
      media_req['Content-Type'] = request.content_type
      media_req.body = request.raw_post
    end

    media_res = Net::HTTP.start(media_uri.hostname, media_uri.port, use_ssl: media_uri.scheme == 'https', open_timeout: 15, read_timeout: 60) do |http|
      http.request(media_req)
    end

    unless media_res.is_a?(Net::HTTPSuccess)
      return render plain: media_res.body, status: media_res.code.to_i, content_type: (media_res['content-type'] || 'application/json')
    end

    media_json = JSON.parse(media_res.body) rescue {}
    file_id = media_json.dig('file', '_id') || media_json['_id']
    unless file_id
      return render plain: media_res.body, status: media_res.code.to_i, content_type: 'application/json'
    end

    confirm_uri = URI("#{rc_base}/api/v1/rooms.mediaConfirm/#{URI.encode_www_form_component(room_id)}/#{URI.encode_www_form_component(file_id)}")
    confirm_req = Net::HTTP::Post.new(confirm_uri)
    confirm_req['X-Auth-Token'] = auth_token
    confirm_req['X-User-Id'] = rc_user_id
    confirm_req['Content-Type'] = 'application/json'
    confirm_req['Accept'] = 'application/json'

    confirm_payload = {}
    confirm_payload['description'] = params[:description].to_s if params[:description].present?
    confirm_payload['tmid'] = params[:tmid].to_s if params[:tmid].present?
    confirm_req.body = confirm_payload.to_json

    confirm_res = Net::HTTP.start(confirm_uri.hostname, confirm_uri.port, use_ssl: confirm_uri.scheme == 'https', open_timeout: 10, read_timeout: 30) do |http|
      http.request(confirm_req)
    end

    render plain: confirm_res.body, status: confirm_res.code.to_i, content_type: (confirm_res['content-type'] || 'application/json')
  end

  def find_project
    @project = Project.find(params[:project_id])
  end

  def ensure_legacy_settings_migrated
    RedmineSubrocketchat::SettingsHelper.migrate_legacy_settings!
  end

  def rc_raw_request(url_str, method: :get, headers: {}, payload: nil)
    uri = URI(url_str)
    req_class = method == :post ? Net::HTTP::Post : Net::HTTP::Get
    req = req_class.new(uri)
    req['Accept'] = 'application/json'
    headers.each { |k, v| req[k] = v if v.present? }
    if payload
      req['Content-Type'] = 'application/json'
      req.body = payload.to_json
    end

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 8, read_timeout: 15) do |http|
      http.request(req)
    end
    parsed = JSON.parse(res.body) rescue {}
    { ok: res.is_a?(Net::HTTPSuccess) && (parsed['status'] == 'success' || parsed['success'] != false), code: res.code.to_i, json: parsed }
  rescue StandardError => e
    { ok: false, code: 0, json: {}, error: e.message }
  end
end
