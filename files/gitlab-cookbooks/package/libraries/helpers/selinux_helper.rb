require_relative '../helpers/shell_out_helper'

class SELinuxHelper
  class << self
    include ShellOutHelper

    def use_unified_policy?(node)
      return false if node['package']['selinux_policy_version'].nil?

      true
    end

    def commands(node, dry_run: false)
      ssh_dir = File.join(node['gitlab']['user']['home'], ".ssh")
      authorized_keys = node['gitlab']['gitlab_shell']['auth_file']
      gitlab_shell_var_dir = node['gitlab']['gitlab_shell']['dir']
      gitlab_shell_config_file = File.join(gitlab_shell_var_dir, "config.yml")
      gitlab_rails_dir = node['gitlab']['gitlab_rails']['dir']
      gitlab_rails_etc_dir = File.join(gitlab_rails_dir, "etc")
      gitlab_shell_secret_file = File.join(gitlab_rails_etc_dir, 'gitlab_shell_secret')
      gitlab_workhorse_sockets_directory = node['gitlab']['gitlab_workhorse']['sockets_directory']
      restorecon_flags = "-v"
      restorecon_flags << " -n" if dry_run

      # If SELinux is enabled, make sure that OpenSSH thinks the .ssh directory and authorized_keys file of the
      # git_user is valid.
      selinux_code = []
      selinux_code << "semanage fcontext -a -t gitlab_shell_t '#{ssh_dir}(/.*)?'"
      selinux_code << "restorecon -R #{restorecon_flags} '#{ssh_dir}'" if File.exist?(ssh_dir)
      [
        authorized_keys,
        gitlab_shell_config_file,
        gitlab_shell_secret_file,
        gitlab_workhorse_sockets_directory
      ].compact.each do |file|
        selinux_code << "semanage fcontext -a -t gitlab_shell_t '#{file}'"
        next unless File.exist?(file)

        selinux_code << "restorecon #{restorecon_flags} '#{file}'"
      end

      selinux_code.join("\n")
    end

    def enabled?
      success?('id -Z')
    end
  end
end
