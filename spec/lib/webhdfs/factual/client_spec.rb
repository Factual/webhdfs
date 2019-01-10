require_relative '../../../../lib/webhdfs/factual'

include WebHDFS::Factual

# FIXME: Migrate shared examples
# require_relative 'shared_examples/target_fs_examples'

def get_client
  Client.new(API_HOST, DEFAULT_NAMENODE)
end

describe Client do
  # FIXME: Migrate shared examples
  it_behaves_like 'a target filesystem interface'
  # it_behaves_like 'a target filesystem implementation'

  context 'when hdfs namenode has changed' do
    before :each do
      allow(InnerClient).to receive(:detect_namenode).and_return('bad_hdfs')
      allow(InnerClient).to receive(:client_working?).and_return(true)
      @bad_hdfs = get_client
    end

    it 'switches to the correct namenode' do
      allow(InnerClient).to receive(:detect_namenode).and_return(DEFAULT_NAMENODE)
      allow(InnerClient).to receive(:client_working?).and_return(true)
      allow(Kernel).to receive(:sleep).and_return(true)
      expect {
        begin
          @bad_hdfs.ls('/')
        rescue WebHDFS::IOError => e
        end
      }.to change {
        @bad_hdfs.instance_eval { @client.host }
      }.to eq DEFAULT_NAMENODE
    end
  end

  it 'retries when a "Cannot obtain block length" error occurs' do
    client = get_client
    allow(Kernel).to receive(:sleep).and_return(true)
    expect(client.instance_eval{@client}).to receive(:list).and_raise(WebHDFS::IOError.new('{"RemoteException":{"exception":"IOException","javaClassName":"java.io.IOException","message":"Cannot obtain block length for L"}}')).twice
    begin
      client.ls('/')
    rescue WebHDFS::IOError
    end
  end

  it 'retries when a ServerError occurs' do
    client = get_client
    allow(Kernel).to receive(:sleep).and_return(true)
    expect(client.instance_eval{@client}).to receive(:list).and_raise(WebHDFS::ServerError.new('Failed to connect to host d495.la.prod.factual.com:1006, execution expired')).twice
    begin
      client.ls('/')
    rescue WebHDFS::ServerError
    end
  end
end
