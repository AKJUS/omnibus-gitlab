require 'spec_helper'

$LOAD_PATH << File.join(__dir__, '../../../../../../files/gitlab-ctl-commands/lib')
$LOAD_PATH << File.join(__dir__, '../../../../../../files/gitlab-ctl-commands-ee/lib')

require 'gitlab_ctl/util'
require 'gitlab_ctl/postgresql/ee'

RSpec.describe GitlabCtl::PostgreSQL::EE do
  describe "#get_primary" do
    before(:each) do
      described_class.instance_variable_set(:@node_attributes, nil)
    end

    context 'when Consul disabled' do
      before do
        allow(GitlabCtl::Util).to receive(:get_node_attributes)
          .and_return({})
      end

      it 'should raise an error' do
        expect { described_class.get_primary } .to raise_error(/Consul agent is not enabled/)
      end
    end

    context 'when PostgreSQL service name is not defined' do
      before do
        allow(GitlabCtl::Util).to receive(:get_node_attributes)
          .and_return(
            {
              'consul' => {
                'enable' => true,
              }
            }
          )
      end

      it 'should raise an error' do
        expect { described_class.get_primary } .to raise_error(/PostgreSQL service name is not defined/)
      end
    end

    context 'when required settings are available' do
      before do
        allow(GitlabCtl::Util).to receive(:get_node_attributes)
          .and_return(
            {
              'consul' => {
                'enable' => true,
              },
              'patroni' => {
                'scope' => 'fake'
              }
            }
          )
        allow_any_instance_of(Resolv::DNS).to receive(:getresources)
          .with('master.fake.service.consul', Resolv::DNS::Resource::IN::SRV)
          .and_return([Struct.new(:target, :port).new('fake.address', 6432)])
        allow_any_instance_of(Resolv::DNS).to receive(:getaddress)
          .with('fake.address')
          .and_return('1.2.3.4')
      end

      it 'should expect consul to listen for dns on port 8600' do
        expect(described_class.consul_dns_port).to be(8600)
      end

      it 'should get the list of PostgreSQL endpoints' do
        expect(described_class.get_primary).to eq ['1.2.3.4:6432']
      end
    end
    context 'when consul has a dns port override' do
      before do
        allow(GitlabCtl::Util).to receive(:get_node_attributes)
          .and_return(
            {
              'consul' => {
                'enable' => true,
                'configuration' => {
                  "ports" => {
                    "dns" => 18600
                  }
                }
              },
              'patroni' => {
                'scope' => 'fake'
              }
            }
          )
        allow_any_instance_of(Resolv::DNS).to receive(:getresources)
          .with('master.fake.service.consul', Resolv::DNS::Resource::IN::SRV)
          .and_return([Struct.new(:target, :port).new('fake.address', 6432)])
        allow_any_instance_of(Resolv::DNS).to receive(:getaddress)
          .with('fake.address')
          .and_return('1.2.3.4')
      end

      it 'should expect consul to listen at the user configured port' do
        expect(described_class.consul_dns_port).to be(18600)
      end
    end
  end
end
