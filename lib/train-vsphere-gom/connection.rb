require "resolv" unless defined?(Resolv)
require "rbvmomi" unless defined?(RbVmomi)

require_relative "guest_operations"

module TrainPlugins
  module VsphereGom
    class Connection < Train::Plugins::Transport::BaseConnection
      attr_reader :options, :config

      attr_writer :logger, :vim, :vm, :vm_guest

      def initialize(config = {})
        @config = config

        unless vm
          logger.error format("[VSphere-GOM] Could not find VM for '%<id>s'. Check power status, if searched via IP", id: config[:host])
          return
        end

        logger.debug format("[VSphere-GOM] Found %<id>s for %<search_type>s %<search>s",
                            id: @vm._ref,
                            search: config[:host],
                            search_type: search_type(config[:host]))

        super(config)
      end

      def close
        return unless vim

        vim.close
        logger.info format("[VSphere-GOM] Closed connection to %<vm>s (VCenter %<vcenter>s)",
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
        logger.debug format("[VSphere-GOM] Copy %<locals>s to %<remote>s",
                            locals: Array(locals).join(", "),
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
        logger.debug format("[VSphere-GOM] Download %<remotes>s to %<local>s",
                            remotes: Array(Remotes).join(","),
                            local: local)

        Array(remotes).each do |remote|
          localfile = File.join(local, File.basename(remote))
          vm_guest.download_file(remote, localfile)
        end
      end

      def run_command_via_connection(command)
        logger.debug format("[VSphere-GOM] Sending command to %<vm>s (VCenter %<vcenter>s)",
                            vm: options[:host],
                            vcenter: options[:vcenter_server])

        result = vm_guest.run(command, shell_type: config[:shell_type].to_sym, timeout: config[:timeout].to_i)

        if windows? && result.exit_status != 0
          logger.debug format("[VSphere-GOM] Received Windows exit code: %<hexcode>s",
                              hexcode: hexit_code(result.exit_status))
        end

        result
      end

      private

      def vim
        @vim ||= RbVmomi::VIM.connect(
          user: config[:vcenter_username],
          password: config[:vcenter_password],
          insecure: config[:vcenter_insecure],
          host: config[:vcenter_server]
        )
      end

      def vm
        @vm ||= find_vm(config[:host])
      end

      def logger
        return @logger if @logger

        @logger = config[:logger] || Logger.new($stdout, level: :info)
      end

      def vm_guest
        return @vm_guest if @vm_guest

        username   = config[:user] || config[:username]
        password   = config[:password]
        ssl_verify = !config[:vcenter_insecure]
        quick      = config[:quick]

        @vm_guest = Support::GuestOperations.new(vim, vm, username, password, ssl_verify: ssl_verify, quick: quick)
        @vm_guest.logger = logger
        @vm_guest
      end

      def os_family
        return vm.guest.guestFamily == "windowsGuest" ? :windows : :linux if vm.guest.guestFamily

        # VMware tools are not initialized or missing, infer from Guest Id
        vm.config&.guestId =~ /^[Ww]in/ ? :windows : :linux
      end

      def linux?
        os_family == :linux
      end

      def windows?
        os_family == :windows
      end

      def hexit_code(exit_code)
        exit_code += 2.pow(32) if exit_code < 0

        "0x" + exit_code.to_s(16).upcase
      end

      def find_vm(needle)
        root_folder = vim.serviceInstance.content.rootFolder

        if ip?(needle)
          root_folder.findByIp(config[:host])
        elsif uuid?(needle)
          root_folder.findByUuid(config[:host])
        elsif inventory_path?(needle)
          root_folder.findByInventoryPath(config[:host])
        else
          root_folder.findByDnsName(config[:host])
        end
      end

      def ip?(ip_string)
        ip_string.match? Resolv::IPv4::Regex
      end

      def uuid?(uuid)
        uuid.downcase.match?(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)
      end

      def inventory_path?(path)
        path.include? "/"
      end

      def moref?(ref)
        ref.match?(/vm-[0-9]*/)
      end

      def search_type(needle)
        return "IP" if ip?(needle)
        return "UUID" if uuid?(needle)
        return "PATH" if inventory_path?(needle)

        "DNS"
      end
    end
  end
end
