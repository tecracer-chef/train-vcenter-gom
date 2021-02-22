require "rbvmomi" unless defined?(RbVmomi)
require "net/http" unless defined?(Net::HTTP)

class Support
  # Encapsulate VMware Tools GOM interaction, originally inspired by github:dnuffer/raidopt
  class GuestOperations
    SHELL_TYPES = {
      linux: {
        cmd:    '/bin/sh',
        suffix: '.sh',
        args:   '-c ". %<cmdfile>s" > %<outfile>s 2> %<errfile>s'
      },

      # TODO: Test
      cmd: {
        cmd:    'cmd.exe',
        suffix: '.cmd',
        args:   '/c "%<cmdfile>s" > %<outfile>s 2> %<errfile>s',
      },

      # TODO
      powershell: {
        cmd:    'C:\Windows\System32\WindowsPowershell\v1.0\powershell.exe',
        suffix: '.ps1',
        # args:   '-ExecutionPolicy Bypass -File %<cmdfile>s >%<outfile>s 2>%<errfile>s',
        args:   '-ExecutionPolicy Bypass -File %<cmdfile>s 2> %<errfile>s | Out-File -FilePath %<outfile>s -Encoding ASCII',
      }
    }.freeze

    attr_writer :gom, :logger

    def initialize(vim, vm, username, password, ssl_verify: true, logger: nil, cleanup: true)
      @vim = vim
      @vm = vm

      @guest_auth = RbVmomi::VIM::NamePasswordAuthentication(interactiveSession: false, username: username, password: password)

      @ssl_verify = ssl_verify
      @cleanup = cleanup
    end

    # Required privileges: VirtualMachine.GuestOperations.Execute, VirtualMachine.GuestOperations.Modify
    def run(command, shell_type = :auto, timeout = 60.0)
      logger.debug format("Running '%s' remotely", command)

      if shell_type == :auto
        shell_type = :linux if linux?
        shell_type = :powershell if windows?
      end

      shell = SHELL_TYPES[shell_type]
      raise "Unsupported shell type #{shell_type.to_s}" unless shell

      temp_file = write_temp_file(command, suffix: shell[:suffix] || "")
      temp_out  = "#{temp_file}-out.txt"
      temp_err  = "#{temp_file}-err.txt"

      begin
        args = format(shell[:args], cmdfile: temp_file, outfile: temp_out, errfile: temp_err)
        exit_code = run_program(shell[:cmd], args, timeout)
      rescue StandardError
        proc_err = read_file(temp_err)
        raise format("Error executing command %s. Exit code: %d. StdErr %s", command, exit_code || -1, proc_err)
      end

      stdout = read_file(temp_out)
      stdout = ascii_only(stdout) if bom?(stdout)

      stderr = read_file(temp_err)

      if cleanup
        delete_file(temp_file)
        delete_file(temp_out)
        delete_file(temp_err)
      end

      ::Train::Extras::CommandResult.new(stdout, stderr, exit_code)
    end

    # Required privilege: VirtualMachine.GuestOperations.Query
    def exist?(remote_file)
      logger.debug format("Checking for remote file %s", remote_file)

      @gom.fileManager.ListFilesInGuest(vm: @vm, auth: @guest_auth, filePath: remote_file)

      true
    rescue RbVmomi::Fault
      false
    end

    def read_file(remote_file)
      return "" unless exist?(remote_file)

      download_file(remote_file, nil)
    end

    # Required privilege: VirtualMachine.GuestOperations.Modify
    def write_file(remote_file, contents)
      logger.debug format("Writing to remote file %s", remote_file)

      put_url = @gom.fileManager.InitiateFileTransferToGuest(
        vm: @vm,
        auth: @guest_auth,
        guestFilePath: remote_file,
        fileAttributes: RbVmomi::VIM::GuestFileAttributes(),
        fileSize: contents.size,
        overwrite: true
      )

      # VCenter internal name might mismatch the external, so fix it
      put_url = put_url.gsub(%r{^https://\*:}, format("https://%s:%s", @vm._connection.host, put_url))
      uri = URI.parse(put_url)

      request = Net::HTTP::Put.new(uri.request_uri)
      request["Transfer-Encoding"] = "chunked"
      request["Content-Length"] = contents.size
      request.body = contents

      http_request(put_url, request)
    rescue RbVmomi::Fault => e
      logger.error "Error during upload, check permissions on remote system: '" + e.message + "'"
    end

    # Required privilege: VirtualMachine.GuestOperations.Modify
    def write_temp_file(contents, prefix: "", suffix: "")
      logger.debug format("Writing to temporary remote file")

      temp_name = @gom.fileManager.CreateTemporaryFileInGuest(vm: @vm, auth: @guest_auth, prefix: prefix, suffix:suffix)
      write_file(temp_name, contents)

      temp_name
    end

    # Required privilege: VirtualMachine.GuestOperations.Modify
    def upload_file(local_file, remote_file)
      logger.debug format("Uploading %s to remote file %s", local_file, remote_file)

      write_file(remote_file, File.open(local_file, "rb").read)
    end

    # Required privilege: VirtualMachine.GuestOperations.Modify
    def download_file(remote_file, local_file)
      logger.debug format("Downloading remote file %s to %s", local_file, remote_file)

      info = @gom.fileManager.InitiateFileTransferFromGuest(vm: @vm, auth: @guest_auth, guestFilePath: remote_file)
      uri = URI.parse(info.url)

      request = Net::HTTP::Get.new(uri.request_uri)
      response = http_request(put_url, request)

      if response.body.size != info.size
        raise format("Downloaded file has different size than reported: %s (%d bytes instead of %d bytes)", remote_file, response.body.size, info.size)
      end

      local_file.nil? ? response.body : File.open(local_file, "w") { |file| file.write(response.body) }
    end

    # Required privilege: VirtualMachine.GuestOperations.Modify
    def delete_file(remote_file)
      logger.debug format("Deleting remote file %s", remote_file)

      @gom.fileManager.DeleteFileInGuest(vm: @vm, auth: @guest_auth, filePath: remote_file)

      true
    rescue RbVmomi::Fault => e
      raise unless e.message.start_with? "FileNotFound:"
      false
    end

    # Required privilege: VirtualMachine.GuestOperations.Modify
    def delete_directory(remote_dir, recursive: true)
      logger.debug format("Deleting remote directory %s", remote_dir)

      @gom.fileManager.DeleteDirectoryInGuest(vm: @vm, auth: @guest_auth, directoryPath: remote_dir, recursive: recursive)

      true
    rescue RbVmomi::Fault => e
      raise if e.message.start_with? "NotADirectory:"
      false
    end

    private

    def gom
      @gom ||= @vim.serviceContent.guestOperationsManager
    end

    def logger
      @logger ||= Logger.new($stdout, level: :info)
    end

    def ascii_only(string)
      string.bytes[2..].map(&:chr).join.delete("\000")
    end

    def bom?(string)
      string.bytes[0..1] == [0xFF, 0xFE]
    end

    def http_request(url, request_data)
      uri = URI.parse(url)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.verify_mode = @ssl_verify ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE

      http.request(request_data)
    end

    def linux?
      os_family == :linux
    end

    def windows?
      os_family == :windows
    end

    def os_family
      return @vm.guest.guestFamily == "windowsGuest" ? :windows : :linux if @vm.guest.guestFamily

      # VMware tools are not initialized or missing, infer from Guest ID
      @vm.config&.guestId&.match(/^win/) ? :windows : :linux
    end

    def run_program(path, args = "", timeout = 60.0)
      logger.debug format("Running %s %s", path, args)

      pid = @gom.processManager.StartProgramInGuest(vm: @vm, auth: @guest_auth, spec: RbVmomi::VIM::GuestProgramSpec.new(programPath: path, arguments: args))
      wait_for_process_exit(pid, timeout)

      process_exit_code(pid)
    end

    def wait_for_process_exit(pid, timeout = 60.0, interval = 1.0)
      start = Time.new

      loop do
        return unless process_running?(pid)
        break if (Time.new - start) >= timeout

        sleep interval
      end

      raise format("Timeout waiting for process %d to exit after %d seconds", pid, timeout) if (Time.new - start) >= timeout
    end

    def process_running?(pid)
      procs = @gom.processManager.ListProcessesInGuest(vm: @vm, auth: @guest_auth, pids: [pid])
      procs.empty? || procs.any? { |gpi| gpi.exitCode.nil? }
    end

    def process_exit_code(pid)
      gom.processManager.ListProcessesInGuest(vm: @vm, auth: @guest_auth, pids: [pid])&.first&.exitCode
    end
  end
end
