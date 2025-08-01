require 'io/console'
require 'rainbow/ext/string'

# For testing purposes, if the first path cannot be found load the second
begin
  require_relative '../../../omnibus-ctl/lib/gitlab_ctl/postgresql'
rescue LoadError
  require_relative '../../../gitlab-ctl-commands/lib/gitlab_ctl/postgresql'
end

module Geo
  class Replication
    attr_accessor :base_path, :data_path, :postgresql_dir_path, :tmp_dir, :ctl
    attr_writer :data_dir, :tmp_data_dir
    attr_reader :options

    DEFAULT_REPLICATION_TIMEOUT_S = 12 * 60 * 60 # 12 hours

    def initialize(instance, options)
      @base_path = instance.base_path
      @data_path = instance.data_path
      @postgresql_dir_path = GitlabCtl::Util.get_public_node_attributes.dig('postgresql', 'dir')
      @ctl = instance
      @options = options
    end

    def postgresql_user
      @postgresql_user ||= GitlabCtl::PostgreSQL.postgresql_username
    end

    def postgresql_group
      @postgresql_group ||= GitlabCtl::PostgreSQL.postgresql_group
    end

    def postgresql_version
      @postgresql_version ||= GitlabCtl::PostgreSQL.postgresql_version
    end

    def check_gitlab_active?
      return unless gitlab_is_active?

      if @options[:force]
        puts "Found data inside the #{db_name} database! Proceeding because --force was supplied".color(:yellow)
      else
        puts "Found data inside the #{db_name} database! If you are sure you are in the secondary server, override with --force".color(:red)
        exit 1
      end
    end

    def check_service_enabled?
      return if ctl.service_enabled?('postgresql')

      puts 'There is no PostgreSQL instance enabled in omnibus, exiting...'.color(:red)
      Kernel.exit 1
    end

    def confirm_replication
      return if @options[:now]

      puts '*** Are you sure you want to continue (replicate/no)? ***'.color(:yellow)

      loop do
        print 'Confirmation: '
        answer = STDIN.gets.to_s.strip

        break if answer == 'replicate'

        exit 0 if answer == 'no'

        puts "*** You entered `#{answer}` instead of `replicate` or `no`.".color(:red)
      end
    end

    def print_warning
      puts
      puts '---------------------------------------------------------------'.color(:yellow)
      puts 'WARNING: Make sure this script is run from the secondary server'.color(:yellow)
      puts '---------------------------------------------------------------'.color(:yellow)
      puts
      puts '*** You are about to delete your local PostgreSQL database, and replicate the primary database. ***'.color(:yellow)
      puts "*** The primary geo node is `#{@options[:host]}` ***".color(:yellow)
      puts
    end

    def execute
      check_gitlab_active?
      check_service_enabled?

      print_warning
      confirm_replication

      @options[:password] = ask_pass

      create_gitlab_backup!

      puts '* Stopping PostgreSQL and all GitLab services'.color(:green)
      run_command('gitlab-ctl stop')

      @pgpass = "#{postgresql_dir_path}/.pgpass"
      create_pgpass_file!

      check_and_create_replication_slot!

      orig_conf = "#{postgresql_dir_path}/data/postgresql.conf"
      if File.exist?(orig_conf)
        puts '* Backing up postgresql.conf'.color(:green)
        run_command("mv #{orig_conf} #{postgresql_dir_path}/")
      end

      bkp_dir = "#{postgresql_dir_path}/data.#{Time.now.to_i}"
      puts "* Moving old data directory to '#{bkp_dir}'".color(:green)

      run_command("mv #{postgresql_dir_path}/data #{bkp_dir}")

      puts "* Starting base backup as the replicator user (#{@options[:user]})".color(:green)

      run_command(pg_basebackup_command,
                  live: true, timeout: backup_timeout)

      puts '* Restoring postgresql.conf'.color(:green)
      run_command("mv #{postgresql_dir_path}/postgresql.conf #{postgresql_dir_path}/data/")

      write_replication_settings!

      puts '* Setting ownership permissions in PostgreSQL data directory'.color(:green)
      run_command("chown -R #{postgresql_user}:#{postgresql_group} #{postgresql_dir_path}/data")

      puts '* Starting PostgreSQL and all GitLab services'.color(:green)
      run_command('gitlab-ctl start')
    end

    def check_and_create_replication_slot!
      return if @options[:skip_replication_slot]

      puts "* Checking for replication slot #{@options[:slot_name]}".color(:green)
      return if replication_slot_exists?

      puts "* Creating replication slot #{@options[:slot_name]}".color(:green)
      create_replication_slot!
    end

    def write_replication_settings!
      write_recovery_settings!
      create_standby_file!
    end

    private

    def backup_timeout
      @options[:backup_timeout] || DEFAULT_REPLICATION_TIMEOUT_S
    end

    def create_gitlab_backup!
      return if @options[:skip_backup]
      return unless gitlab_bootstrapped? && database_exists? && table_exists?('projects')

      puts '* Executing GitLab backup task to prevent accidental data loss'.color(:green)
      run_command('gitlab-rake gitlab:backup:create')
    end

    def create_pgpass_file!
      File.open(@pgpass, 'w', 0600) do |file|
        file.write(<<~EOF
          #{@options[:host]}:#{@options[:port]}:*:#{@options[:user]}:#{@options[:password]}
        EOF
                  )
      end
      run_command("chown #{postgresql_user}:#{postgresql_group} #{@pgpass}")
    end

    def write_recovery_settings!
      geo_conf_file = "#{postgresql_dir_path}/data/gitlab-geo.conf"
      File.open(geo_conf_file, "w", 0640) do |file|
        settings = <<~EOF
          # - Added by GitLab Omnibus for Geo replication -
          recovery_target_timeline = '#{@options[:recovery_target_timeline]}'
          primary_conninfo = 'host=#{@options[:host]} port=#{@options[:port]} user=#{@options[:user]} password=#{@options[:password]} sslmode=#{@options[:sslmode]} sslcompression=#{@options[:sslcompression]}'
        EOF

        file.write(settings)
        file.write("primary_slot_name = '#{@options[:slot_name]}'\n") if @options[:slot_name]
      end
    end

    def create_standby_file!
      standby_file = "#{postgresql_dir_path}/data/standby.signal"
      File.write(standby_file, "")
      run_command("chown #{postgresql_user}:#{postgresql_group} #{standby_file}")
    end

    def ask_pass
      GitlabCtl::Util.get_password(input_text: "Enter the password for #{@options[:user]}@#{@options[:host]}: ", do_confirm: false)
    end

    def replication_slot_exists?
      status = run_psql_command("SELECT slot_name FROM pg_replication_slots WHERE slot_name = '#{@options[:slot_name]}';")
      status.stdout.include?(@options[:slot_name])
    end

    def create_replication_slot!
      status = run_psql_command("SELECT slot_name FROM pg_create_physical_replication_slot('#{@options[:slot_name]}');")
      status.stdout.include?(@options[:slot_name])
    end

    def pg_basebackup_command
      slot_arguments =
        if @options[:skip_replication_slot]
          ''
        else
          "-S #{@options[:slot_name]}"
        end

      %W(
        PGPASSFILE=#{@pgpass} #{@base_path}/embedded/bin/pg_basebackup
        -h #{@options[:host]}
        -p #{@options[:port]}
        -D #{@postgresql_dir_path}/data
        -U #{@options[:user]}
        -v
        -P
        -X stream
        #{slot_arguments}
      ).join(' ')
    end

    def run_psql_command(query)
      cmd = %(PGPASSFILE=#{@pgpass} #{base_path}/bin/gitlab-psql -h #{@options[:host]} -p #{@options[:port]} -U #{@options[:user]} -d #{db_name} -t -c "#{query}")
      run_command(cmd, live: false)
    end

    def run_command(cmd, live: false, timeout: nil)
      status = GitlabCtl::Util.run_command(cmd, live: live, timeout: timeout)
      if status.error?
        puts status.stdout
        puts status.stderr
        teardown(cmd)
      end

      status
    end

    def run_query(query)
      status = GitlabCtl::Util.run_command(
        "#{base_path}/bin/gitlab-psql -d #{db_name} -c '#{query}' -q -t"
      )
      status.error? ? false : status.stdout.strip
    end

    def gitlab_bootstrapped?
      File.exist?("#{data_path}/bootstrapped")
    end

    def database_exists?
      status = GitlabCtl::Util.run_command("#{base_path}/bin/gitlab-psql -d template1 -c 'SELECT datname FROM pg_database' -A | grep -x #{db_name}")
      !status.error?
    end

    def table_exists?(table_name)
      query = "SELECT table_name
                 FROM information_schema.tables
                WHERE table_catalog = '#{db_name}'
                  AND table_schema='public'"
      status = GitlabCtl::Util.run_command("#{base_path}/bin/gitlab-psql -d #{db_name} -c \"#{query}\" -A | grep -x #{table_name}")
      !status.error?
    end

    def table_empty?(table_name)
      output = run_query('SELECT 1 FROM projects LIMIT 1')
      output == '1' ? false : true
    end

    def gitlab_is_active?
      system("gitlab-rake", "gitlab:db:active")
    end

    def db_name
      @options[:db_name]
    end

    def teardown(cmd)
      puts <<~MESSAGE.color(:red)
        *** Initial replication failed! ***

        Replication tool returned with a non zero exit status!

        Troubleshooting tips:
          - replication should be run by root user
          - check if `roles ['geo_primary_role']` or `geo_primary_role['enable'] = true` exists in `gitlab.rb` on the primary node
          - check your trust settings `md5_auth_cidr_addresses` in `gitlab.rb` on the primary node

        Failed to execute: #{cmd}
      MESSAGE

      exit 1
    end
  end
end
