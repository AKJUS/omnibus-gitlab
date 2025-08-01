require 'chef_helper'

RSpec.describe 'monitoring::redis-exporter' do
  let(:chef_run) { ChefSpec::SoloRunner.new(step_into: %w(runit_service)).converge('gitlab::default') }
  let(:node) { chef_run.node }
  let(:default_vars) do
    {
      'SSL_CERT_DIR' => '/opt/gitlab/embedded/ssl/certs/',
      'GODEBUG' => 'tlsmlkem=0',
    }
  end

  before do
    allow(Gitlab).to receive(:[]).and_call_original
  end

  context 'when redis is disabled locally' do
    before do
      stub_gitlab_rb(
        redis: { enable: false }
      )
    end

    it 'defaults the redis-exporter to being disabled' do
      expect(node['monitoring']['redis_exporter']['enable']).to eq false
    end

    it 'allows redis-exporter to be explicitly enabled' do
      stub_gitlab_rb(redis_exporter: { enable: true })

      expect(node['monitoring']['redis_exporter']['enable']).to eq true
    end
  end

  context 'when redis-exporter is enabled' do
    let(:config_template) { chef_run.template('/opt/gitlab/sv/redis-exporter/log/config') }

    before do
      stub_gitlab_rb(
        redis_exporter: { enable: true }
      )
    end

    it_behaves_like 'enabled runit service', 'redis-exporter', 'root', 'root'

    it 'creates necessary env variable files' do
      expect(chef_run).to create_env_dir('/opt/gitlab/etc/redis-exporter/env').with_variables(default_vars)
    end

    it 'populates the files with expected configuration' do
      expect(config_template).to notify('ruby_block[reload_log_service]')

      expect(chef_run).to render_file('/opt/gitlab/sv/redis-exporter/run')
        .with_content { |content|
          expect(content).to match(/exec chpst -P/)
          expect(content).to match(/\/opt\/gitlab\/embedded\/bin\/redis_exporter/)
        }

      expect(chef_run).to render_file('/opt/gitlab/sv/redis-exporter/log/run')
        .with_content(/svlogd -tt \/var\/log\/gitlab\/redis-exporter/)
    end

    it 'sets default flags' do
      expect(chef_run).to render_file('/opt/gitlab/sv/redis-exporter/run')
        .with_content(/web.listen-address=localhost:9121/)
      expect(chef_run).to render_file('/opt/gitlab/sv/redis-exporter/run')
        .with_content(%r{redis.addr=unix:///var/opt/gitlab/redis/redis.socket})
    end
  end

  context 'when redis-exporter is enabled for an external Redis' do
    let(:config_template) { chef_run.template('/opt/gitlab/sv/redis-exporter/log/config') }

    before do
      stub_gitlab_rb(
        redis_exporter: { enable: true },
        gitlab_rails: {
          redis_host: '1.2.3.4',
          redis_port: 6378,
          redis_ssl: true,
          redis_password: 'some-password',
          redis_enable_client: false
        }
      )
    end

    it_behaves_like 'enabled runit service', 'redis-exporter', 'root', 'root'

    it 'sets flags' do
      expect(chef_run).to render_file('/opt/gitlab/sv/redis-exporter/run')
        .with_content(/web.listen-address=localhost:9121/)
      expect(chef_run).to render_file('/opt/gitlab/sv/redis-exporter/run')
        .with_content(%r{redis.addr=rediss://:some-password@1.2.3.4:6378/})
      expect(chef_run).to render_file('/opt/gitlab/sv/redis-exporter/run')
        .with_content(/--set-client-name=false/)
    end
  end

  context 'when log dir is changed' do
    before do
      stub_gitlab_rb(
        redis_exporter: {
          log_directory: 'foo',
          enable: true
        }
      )
    end

    it 'populates the files with expected configuration' do
      expect(chef_run).to render_file('/opt/gitlab/sv/redis-exporter/log/run')
        .with_content(/svlogd -tt foo/)
    end
  end

  context 'with user provided settings' do
    before do
      stub_gitlab_rb(
        redis_exporter: {
          flags: {
            'redis.addr' => '/tmp/socket',
            'redis.password' => 'password<(',
          },
          listen_address: 'localhost:9900',
          enable: true,
          env: {
            'USER_SETTING' => 'asdf1234'
          }
        }
      )
    end

    it 'populates the files with expected configuration' do
      expect(chef_run).to render_file('/opt/gitlab/sv/redis-exporter/run')
        .with_content(/web.listen-address=localhost:9900/)
      expect(chef_run).to render_file('/opt/gitlab/sv/redis-exporter/run')
        .with_content(%r{redis.addr=/tmp/socket})
      expect(chef_run).to render_file('/opt/gitlab/sv/redis-exporter/run')
        .with_content(/redis.password=password\\<\\/)
    end

    it 'creates necessary env variable files' do
      expect(chef_run).to create_env_dir('/opt/gitlab/etc/redis-exporter/env').with_variables(
        default_vars.merge(
          {
            'USER_SETTING' => 'asdf1234'
          }
        )
      )
    end
  end

  context 'log directory and runit group' do
    context 'default values' do
      before do
        stub_gitlab_rb(redis_exporter: { enable: true })
      end
      it_behaves_like 'enabled logged service', 'redis-exporter', true, { log_directory_owner: 'gitlab-redis' }
    end

    context 'custom values' do
      before do
        stub_gitlab_rb(
          redis_exporter: {
            enable: true,
            log_group: 'fugee'
          }
        )
      end
      it_behaves_like 'enabled logged service', 'redis-exporter', true, { log_directory_owner: 'gitlab-redis', log_group: 'fugee' }
    end
  end

  include_examples "consul service discovery", "redis_exporter", "redis-exporter"
end
