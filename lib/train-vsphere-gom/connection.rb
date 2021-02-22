require 'rbvmomi' unless defined?(RbVmomi)

require_relative 'guest_operations'

module TrainPlugins
  module VsphereGom
    class Connection < Train::Plugins::Transport::BaseConnection
      attr_reader :vim, :vm, :vm_guest, :options, :logger

      def initialize(config = {})
        # Connect vCenter
        @vim = RbVmomi::VIM.connect(
          user: config[:vcenter_username],
          password: config[:vcenter_password],
          insecure: config[:vcenter_insecure],
          host: config[:vcenter_server]
        )

        # Get VM and settings
        root_folder = vim.serviceInstance.content.rootFolder
        @vm = root_folder.findByIp(config[:host]) # TODO: also by Name/Path
        @logger = config[:logger] || Logger.new($stdout, level: :info)

        if vm.nil?
          logger.error format("[VSphere-GOM] Could not find VM for '%<id>s'", id: config[:host])
          return
        end

        username   = config[:user]
        password   = config[:password]
        ssl_verify = !config[:vcenter_insecure]

        @vm_guest = Support::GuestOperations.new(vim, vm, username, password, ssl_verify: ssl_verify)
        @vm_guest.logger = logger

        super(config)
      end

      def close
        return if @vim.nil?

        @vim.close
        logger.info format('[VSphere-GOM] Closed connection to %<vm>s (VCenter %<vcenter>s)',
                           vm: options[:host],
                           vcenter: options[:vcenter_server])
      end

      def uri
        "vsphere-gom://#{options[:user]}@#{options[:vcenter_server]}/#{options[:host]}"
      end

      def file_via_connection(path, *args)
        if windows?
          Train::File::Remote::Windows.new(self, path, *args)
        else
          Train::File::Remote::Unix.new(self, path, *args)
        end
      end

      def upload(locals, remote)
        logger.debug format('Copy %<locals>s to %<remote>s',
                            locals: Array(locals).join(', '),
                            remote: remote)

        # Collect recursive list of directories and files
        all = Array(locals).map do |local|
          File.directory?(local) ? Dir.glob("#{local}/**/*") : local
        end.flatten

        dirs = all.select { |obj| File.directory? obj }
        dirs.each { |dir| tools.create_dir(dir) }

        # Then upload all files
        files = all.select { |obj| File.file? obj }
        files.each do |local|
          remotefile = path(remote, File.basename(local))
          vm_guest.upload_file(local, remotefile)
        end
      end

      def download(remotes, local)
        logger.debug format('Download %<remotes>s to %<local>s',
                            remotes: Array(Remotes).join(','),
                            local: local)

        Array(remotes).each do |remote|
          localfile = File.join(local, File.basename(remote))
          vm_guest.download_file(remote, localfile)
        end
      end

      def run_command_via_connection(command)
        logger.debug format('[VSphere-GOM] Sending command to %<vm>s (VCenter %<vcenter>s)',
                            vm: options[:host],
                            vcenter: options[:vcenter_server])

        vm_guest.run(command)
      end

      private

      def os_family
        return vm.guest.guestFamily == 'windowsGuest' ? :windows : :linux if vm.guest.guestFamily

        # VMware tools are not initialized or missing, infer from Guest Id
        vm.config&.guestId =~ /^[Ww]in/ ? :windows : :linux
      end

      def linux?
        os_family == :linux
      end

      def windows?
        os_family == :windows
      end
    end
  end
end
