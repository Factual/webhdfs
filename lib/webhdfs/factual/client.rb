module WebHDFS
  module Factual
    class Client
      def initialize(api, default_namenode)
        @api = api
        @default_namenode = default_namenode
        @client = get_client
      end

      def get_client
        InnerClient.setup(@api, @default_namenode)
      end

      def append(path, data)
        smart_retry do
          begin
            @client.stat(path)
            @client.append(path, data + "\n")
          rescue WebHDFS::FileNotFoundError
            @client.create(path, data + "\n")
          end
        end
      end

      def rm_r(path)
        rm_r!(path)
      # rescue NeutronicHelper::FileNotFoundError
      rescue WebHDFS::FileNotFoundError
        nil
      end

      def rm_r!(path)
        smart_retry do
          begin
            @client.stat(path)
          rescue WebHDFS::FileNotFoundError => e
            # raise NeutronicHelper::FileNotFoundError, "File #{path} not found"
            raise WebHDFS::FileNotFoundError, "File #{path} not found", e.backtrace
          end
          @client.delete(path, recursive: true)
        end
      end

      def ls(path)
        smart_retry do
          @client.list(path).map{ |f| f['pathSuffix'] }
        end
      end

      def mkdir(path)
        smart_retry do
          @client.mkdir(path, permission: '0775')
        end
      end

      def mv(paths, target_dir)
        paths.each do |path|
          smart_retry do
            @client.rename(path, File.join(target_dir, File.basename(path)))
          end
        end
      end

      def read(path)
        smart_retry do
          rescue_read_errors(path) do
            @client.read(path)
          end
        end
      end

      def tip_of_tail(path)
        read(path).split("\n").last || ''
      end

      def content(path)
        smart_retry do
          @client.content_summary(path)
        end
      end

      def mtime(path)
        smart_retry do
          begin
            modification_time = @client.stat(path)['modificationTime']
          rescue WebHDFS::FileNotFoundError => e
            # raise NeutronicHelper::FileNotFoundError, "File #{path} not found"
            raise WebHDFS::FileNotFoundError, "File #{path} not found", e.backtrace
          end
          Time.at(modification_time / 1000)
        end
      end

      private

      def smart_retry(&block)
        block.call
      rescue WebHDFS::IOError => e
        specific_exception = JSON.parse(e.message)['RemoteException']['exception'] rescue nil
        message = JSON.parse(e.message)['RemoteException']['message'] rescue nil
        if specific_exception == 'StandbyException'
          WebHDFS::Factual::logger.error("HDFS namenode in standby. Sleeping for 10 seconds and then attempting to reconnect.")
          Kernel.sleep 10
          @client = get_client
          block.call
        elsif message =~ /^Cannot obtain block length/
          WebHDFS::Factual::logger.error(e.message)
          Kernel.sleep 5
          block.call
        else
          raise
        end
      rescue WebHDFS::ServerError => e
        WebHDFS::Factual::logger.error(e.message)
        Kernel.sleep 15
        block.call
      rescue WebHDFS::KerberosError => e
        WebHDFS::Factual::logger.error("Kerberos credentials expired, refreshing them.")
        @client = get_client
        block.call
      end

      def rescue_read_errors(path, &block)
        block.call
      rescue WebHDFS::FileNotFoundError => e
        begin
          message = JSON.parse(e.message)["RemoteException"]["message"]
        rescue StandardError
          message = e.message
        end
        if message =~ /not found/
          # raise NeutronicHelper::FileNotFoundError, message, e.backtrace
          raise WebHDFS::FileNotFoundError, message, e.backtrace
        else
          raise InvalidOpError, message, e.backtrace
        end
      end
    end
  end
end
