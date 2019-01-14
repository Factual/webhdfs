require_relative '../../../lib/webhdfs'

include WebHDFS

require_relative '../../shared_examples/target_fs_examples'

# NOTE: Client's initializer used to get from jmx, so tests assume that
# TODO: Rename API_HOST to JMX_HOST
def get_client
  client = Client.new do |c|
    c.host = DEFAULT_NAMENODE
    c.jmx_host = API_HOST
    c.kerberos = true
    c.kerberos_keytab = ENV['KEYTAB_PATH']
    c.retry_known_errors = true
    c.retry_times = 3
  end

  client.set_namenode_from_jmx
  client.ensure_operational
  client
end

describe Client do
  it_behaves_like 'a target filesystem interface'
  it_behaves_like 'a target filesystem implementation'

  describe '#get_namenode_from_jmx' do
    it 'returns the correct namenode' do
      client = get_client
      # TODO: This pattern should also accept API_HOST
      stub_request(:get, /localhost/).to_return(body: fixture('namenode_status.json'))
      expect(client.get_namenode_from_jmx).to eq(DEFAULT_NAMENODE)
    end

    it 'returns the default namenode when request fails' do
      client = get_client
      client.host = 'remain'
      stub_request(:get, /localhost/).to_return(status: 500)
      expect(client.host).to eq('remain')
      allow_any_instance_of(WebHDFS::ClientV1).to receive(:get_namenode_from_jmx).and_raise(WebHDFS::Error.new("Whatever"))
      client.set_namenode_from_jmx
      expect(client.host).to eq('remain')
    end
  end

  context 'when hdfs namenode has changed' do
    before :each do
      allow_any_instance_of(WebHDFS::ClientV1).to receive(:get_namenode_from_jmx).and_return('bad_hdfs')
      allow_any_instance_of(WebHDFS::ClientV1).to receive(:ensure_operational).and_return(true)
      @bad_hdfs = get_client
      @bad_hdfs.set_namenode_from_jmx
      expect(@bad_hdfs.host).to eq('bad_hdfs')
    end

    it 'switches to the correct namenode' do
      allow_any_instance_of(WebHDFS::ClientV1).to receive(:get_namenode_from_jmx).and_return(DEFAULT_NAMENODE)
      allow_any_instance_of(WebHDFS::ClientV1).to receive(:ensure_operational).and_return(true)
      allow(Kernel).to receive(:sleep).and_return(true)
      expect {
        begin
          @bad_hdfs._ls('/')
        rescue WebHDFS::IOError => e
        end
      }.to change {
        @bad_hdfs.host
      }.to eq DEFAULT_NAMENODE
    end
  end

  it 'retries when a "Cannot obtain block length" error occurs' do
    client = get_client
    allow(Kernel).to receive(:sleep).and_return(true)
    expect(client).to receive(:list).and_raise(WebHDFS::IOError.new('{"RemoteException":{"exception":"IOException","javaClassName":"java.io.IOException","message":"Cannot obtain block length for L"}}')).twice
    begin
      client._ls('/')
    rescue WebHDFS::IOError
    end
  end

  it 'retries when a ServerError occurs' do
    client = get_client
    allow(Kernel).to receive(:sleep).and_return(true)
    expect(client).to receive(:list).and_raise(WebHDFS::ServerError.new('Failed to connect to host d495.la.prod.factual.com:1006, execution expired')).twice
    begin
      client._ls('/')
    rescue WebHDFS::ServerError
    end
  end
end