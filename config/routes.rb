Rails.application.routes.draw do
  match 'projects/:project_id/rocket_chat', to: 'rocket_chat#show', via: :get
  match 'projects/:project_id/rocket_chat/session', to: 'rocket_chat#session_config', via: :get
  match 'projects/:project_id/rocket_chat/issues', to: 'rocket_chat#issues', via: :get
  match 'projects/:project_id/rocket_chat/issue_thread/:issue_id', to: 'rocket_chat#issue_thread', via: [:post, :get]
  match 'projects/:project_id/rocket_chat/proxy/*rc_path', to: 'rocket_chat#proxy', via: [:get, :post, :put, :delete], format: false
end
