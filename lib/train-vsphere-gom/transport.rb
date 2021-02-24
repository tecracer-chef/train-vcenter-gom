require "train"
require "train/plugins"
require "train-vsphere-gom/connection"

module TrainPlugins
  module VsphereGom
    class Transport < Train.plugin(1)
      name "vsphere-gom"

      option :vcenter_server, required: true, default: ENV["VI_SERVER"]
      option :vcenter_username, required: true, default: ENV["VI_USERNAME"]
      option :vcenter_password, required: true, default: ENV["VI_PASSWORD"]
      option :vcenter_insecure, required: false, default: true

      option :host, default: ENV["VI_VM"], required: true
      option :user, required: true
      option :password, required: true

      option :quick, default: false
      option :shell_type, default: :auto
      option :timeout, default: 60

      # inspec -t vsphere-gom://
      def connection(_instance_opts = nil)
        @connection ||= TrainPlugins::VsphereGom::Connection.new(@options)
      end
    end
  end
end
