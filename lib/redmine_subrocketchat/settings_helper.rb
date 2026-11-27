# lib/redmine_subrocketchat/settings_helper.rb

module RedmineSubrocketchat
  module SettingsHelper
    # Migrates existing settings from the legacy `plugin_redmine_rocketchat` database record
    # so upgrading from `redmine_rocketchat` v1.x to `redmine_subrocketchat` v2.x is 100% seamless.
    def self.migrate_legacy_settings!
      return if Setting.where(name: 'plugin_redmine_subrocketchat').exists?

      legacy_raw = Setting.where(name: 'plugin_redmine_rocketchat').pick(:value)
      return if legacy_raw.blank?

      clean_raw = legacy_raw.is_a?(String) ? legacy_raw.sub('--- !ruby/hash:ActiveSupport::HashWithIndifferentAccess', '---') : legacy_raw
      legacy_hash = if clean_raw.is_a?(Hash)
                      clean_raw.to_h
                    elsif YAML.respond_to?(:unsafe_load)
                      YAML.unsafe_load(clean_raw).to_h
                    else
                      YAML.load(clean_raw).to_h
                    end

      return if legacy_hash.blank?

      Setting.plugin_redmine_subrocketchat = legacy_hash
      Rails.logger.info('Redmine Subrocketchat: Migrated settings from legacy plugin_redmine_rocketchat.')
    rescue StandardError => e
      Rails.logger.warn("Redmine Subrocketchat: Could not migrate legacy settings (#{e.message})")
    end

    # Updates the Redmine URL (with protocol) in the plugin settings
    def self.update_redmine_url
      protocol = determine_protocol
      redmine_url = "#{protocol}#{Setting.host_name.to_s.chomp('/')}"

      Setting.plugin_redmine_subrocketchat['redmine_host_url'] = redmine_url
      Rails.logger.info("Redmine Subrocketchat: Redmine URL updated to #{redmine_url}")
    end

    # Determines the protocol dynamically (HTTPS or HTTP)
    def self.determine_protocol
      if defined?(RequestStore) && RequestStore.store[:controller]
        request = RequestStore.store[:controller].request
        return request.ssl? ? 'https://' : 'http://'
      end

      Rails.env.production? ? 'https://' : 'http://'
    end
  end
end

# Keep backward-compatible constant alias
RedmineRocketchat = RedmineSubrocketchat unless defined?(RedmineRocketchat)
