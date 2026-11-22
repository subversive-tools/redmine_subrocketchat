# app/controllers/rocket_chat_controller.rb
# Controller for displaying and interacting with Rocket.Chat channels, issue threads, and the Rocket.Chat 8.x compatibility proxy.

class RocketChatController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:proxy]
  before_action :find_project, :authorize

  def show
    # Renders app/views/rocket_chat/show.html.erb
  end

  # GET /projects/:project_id/rocket_chat/session
  # Returns JSON configuration for EmbeddedChat (host, roomId, channelName, authToken, optional issue thread info)
  def session_config
    channel_name = RedmineSubrocketchat::RocketChatHelper.channel_name_for(@project)
    room_id = RedmineSubrocketchat::RocketChatHelper.get_or_create_project_room_id(@project)
    auth_token = RedmineSubrocketchat::RocketChatHelper.create_user_login_token(User.current, project: @project)

    issue_data = nil
    if params[:issue_id].present?
      issue = Issue.visible.where(project_id: @project.self_and_descendants.select(:id)).find_by(id: params[:issue_id])
      if issue
        thread_id = issue.respond_to?(:rocketchat_thread_id) ? issue.rocketchat_thread_id : nil
        thread_msg = thread_id.present? ? RedmineSubrocketchat::RocketChatHelper.get_message(thread_id) : nil

        if thread_msg.nil? && Setting.plugin_redmine_subrocketchat['auto_create_issue_threads'] == 'true'
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

  # Transparent proxy for EmbeddedChat REST & media calls to avoid browser CORS preflight issues
  # and bridge Rocket.Chat 8.x API changes (`rooms.media`, `chat.getThreadMessages`, `groups.files`).
  def proxy
    rc_base = (Setting.plugin_redmine_subrocketchat['rocket_chat_url_internal'].presence ||
               Setting.plugin_redmine_subrocketchat['rocket_chat_url']).to_s.chomp('/')
    rc_path = params[:rc_path].to_s

    # All Redmine project channels are private groups (`groups.*`).
    rc_path = rc_path.sub(/\Aapi\/v1\/channels\.(messages|members|roles|files|info)\z/, 'api/v1/groups.\1')

    if request.method_symbol == :get && rc_path == 'api/v1/settings/Message_MaxAllowedSize'
      return render json: { _id: 'Message_MaxAllowedSize', value: 5000, success: true }, status: :ok
    end

    if request.method_symbol == :post && rc_path =~ /\Aapi\/v1\/rooms\.upload\/([^\/\?]+)\z/
      return proxy_rooms_upload_v8(rc_base, Regexp.last_match(1))
    end

    if request.method_symbol == :get && rc_path =~ /\Aapi\/v1\/(groups|channels)\.messages\z/ && params[:query].present?
      return proxy_messages_with_query_v8(rc_base, rc_path)
    end

    if request.method_symbol == :get && (rc_path == 'api/v1/channels.images' || rc_path == 'api/v1/groups.files')
      return proxy_room_files_v8(rc_base, images_only: rc_path == 'api/v1/channels.images')
    end

    query_str = request.query_string.presence

    target_url = "#{rc_base}/#{rc_path}"
    target_url += "?#{query_str}" if query_str

    uri = URI(target_url)
    method_class = case request.method_symbol
                   when :get then Net::HTTP::Get
                   when :post then Net::HTTP::Post
                   when :put then Net::HTTP::Put
                   when :delete then Net::HTTP::Delete
                   else Net::HTTP::Get
                   end

    req = method_class.new(uri)
    req['Content-Type'] = request.content_type if request.content_type.present?
    req['Accept'] = request.headers['Accept'] || 'application/json'

    auth_token = request.headers['X-Auth-Token'].presence || Setting.plugin_redmine_subrocketchat['rocket_chat_token']
    rc_user_id = request.headers['X-User-Id'].presence || Setting.plugin_redmine_subrocketchat['rocket_chat_user_id']
    req['X-Auth-Token'] = auth_token if auth_token.present?
    req['X-User-Id'] = rc_user_id if rc_user_id.present?
    if auth_token.present? && rc_user_id.present?
      req['Cookie'] = "rc_uid=#{rc_user_id}; rc_token=#{auth_token}"
    end

    if [:post, :put].include?(request.method_symbol)
      body_content = request.raw_post
      req.body = body_content if body_content.present?
    end

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 10, read_timeout: 30) do |http|
      http.request(req)
    end

    render plain: response.body, status: response.code.to_i, content_type: (response['content-type'] || 'application/json')
  rescue StandardError => e
    Rails.logger.error("Rocket.Chat Proxy Error (#{params[:rc_path]}): #{e.message}")
    render json: { status: 'error', error: e.message }, status: :bad_gateway
  end

  private

  # Translates `GET /api/v1/channels.images?roomId=...` and `GET /api/v1/groups.files?roomId=...`
  # so ImageGallery and FileGallery work in private groups and their URLs use our authenticated Redmine proxy.
  def proxy_room_files_v8(rc_base, images_only: false)
    room_id = params[:roomId].to_s
    auth_token = request.headers['X-Auth-Token'].presence || Setting.plugin_redmine_subrocketchat['rocket_chat_token']
    rc_user_id = request.headers['X-User-Id'].presence || Setting.plugin_redmine_subrocketchat['rocket_chat_user_id']

    uri = URI("#{rc_base}/api/v1/groups.files?roomId=#{URI.encode_www_form_component(room_id)}&count=100")
    req = Net::HTTP::Get.new(uri)
    req['X-Auth-Token'] = auth_token if auth_token.present?
    req['X-User-Id'] = rc_user_id if rc_user_id.present?
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

  # Rocket.Chat 7.0+ / 8.x disabled arbitrary MongoDB `query={"tmid":...}` parameters on `groups.messages` / `channels.messages` by default.
  # This helper transparently translates thread queries to `chat.getThreadMessages` and filters top-level room messages (`tmid: {$exists: false}`).
  def proxy_messages_with_query_v8(rc_base, rc_path)
    query_hash = JSON.parse(params[:query].to_s) rescue {}
    tmid_param = query_hash['tmid']
    auth_token = request.headers['X-Auth-Token']
    rc_user_id = request.headers['X-User-Id']

    if tmid_param.is_a?(String) && tmid_param.present?
      uri = URI("#{rc_base}/api/v1/chat.getThreadMessages?tmid=#{URI.encode_www_form_component(tmid_param)}")
      req = Net::HTTP::Get.new(uri)
      req['X-Auth-Token'] = auth_token if auth_token.present?
      req['X-User-Id'] = rc_user_id if rc_user_id.present?
      req['Accept'] = 'application/json'

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 10, read_timeout: 20) do |http|
        http.request(req)
      end

      if res.is_a?(Net::HTTPSuccess)
        data = JSON.parse(res.body) rescue {}
        if data['messages'].is_a?(Array)
          data['messages'] = data['messages']
                               .reject { |m| m['_id'] == tmid_param }
                               .sort_by { |m| m['ts'].to_s }
                               .reverse
        end
        return render json: data, status: :ok
      end
      return render plain: res.body, status: res.code.to_i, content_type: (res['content-type'] || 'application/json')
    end

    room_id = params[:roomId].to_s
    uri = URI("#{rc_base}/#{rc_path}?roomId=#{URI.encode_www_form_component(room_id)}&count=100")
    req = Net::HTTP::Get.new(uri)
    req['X-Auth-Token'] = auth_token if auth_token.present?
    req['X-User-Id'] = rc_user_id if rc_user_id.present?
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
  def proxy_rooms_upload_v8(rc_base, room_id)
    auth_token = request.headers['X-Auth-Token']
    rc_user_id = request.headers['X-User-Id']

    media_uri = URI("#{rc_base}/api/v1/rooms.media/#{URI.encode_www_form_component(room_id)}")
    media_req = Net::HTTP::Post.new(media_uri)
    media_req['X-Auth-Token'] = auth_token if auth_token.present?
    media_req['X-User-Id'] = rc_user_id if rc_user_id.present?
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
    confirm_req['X-Auth-Token'] = auth_token if auth_token.present?
    confirm_req['X-User-Id'] = rc_user_id if rc_user_id.present?
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
end
