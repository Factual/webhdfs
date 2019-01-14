shared_examples 'dir setup' do

  let(:path) do
    File.join(TEST_DIR, 'test_dir')
  end

  before :each do
    get_client.mkdir(path)
  end

  after :each do
    get_client.rm_r(path)
  end
end