# Train-vsphere-gom

`train-vsphere-gom` is a Train plugin and is used as a Train OS Transport to
connect to virtual machines via VMware Tools.

This allows working with machines in different network segments, without
adding routes, NAT or firewall routes.

vSphere Guest Operations Manager covers various use cases within a target VM,
including file transfers, Windows registry access and command execution. It is
used by various 3rd party tools to monitor and manage VMs.

## Requirements

- VMware vSphere 5.0 or higher

## Permissions

Needs login credentials for vCenter (API) as well as the target machine (OS).

Mandatory privileges in vCenter:

- VirtualMachine.GuestOperations.Query
- VirtualMachine.GuestOperations.Execute
- VirtualMachine.GuestOperations.Modify (for file uploads)

## Installation

Install this Gem from rubygems.org:

```bash
gem install train-vsphere-gom
```

## Transport parameters

| Option             | Explanation                                            | Default    | Env. Vars     |
|--------------------|--------------------------------------------------------|------------|---------------|
| `host`             | VM to connect (`host` for Train compatibility)         | _required_ | `VI_VM`       |
| `user`             | VM username for login                                  | _required_ |               |
| `password`         | VM password  for login                                 | _required_ |               |
| `vcenter_server`   | VCenter server                                         | _required_ | `VI_SERVER`   |
| `vcenter_username` | VCenter username                                       | _required_ | `VI_USERNAME` |
| `vcenter_password` | VCenter password                                       | _required_ | `VI_PASSWORD` |
| `vcenter_insecure` | Allow connections when SSL certificate is not matching | `false`    |               |

By design, Train VSphere GOM requires two authentication steps: One to get access to the VCenter API and one
to get access to the guest VM with local credentials.

The environment variables are aligned to those from VMware SDK and ESXCLI.

## Limitations

- SSPI based guest VM logins are not supported yet
- the guest VM (`host`) can only be searched by its IP address. Support for VM name, UUID, MORef etc is planned.

## Example use

```ruby
require 'train-vsphere-gom'

train  = Train.create('vsphere-gom', {
            # Relying on VI_* variables for VCenter configuration
            username: 'Administrator',
            password: 'Password'
            host:     '10.20.30.40',

            logger:   Logger.new($stdout, level: :info)
         })
conn   = train.connection
conn.run_command("Write-Host 'Inside the VM'")
```

## References

- [vSphere Web Services: GOM](https://code.vmware.com/docs/5722/vsphere-web-services-api-reference/doc/vim.vm.guest.GuestOperationsManager.html)
