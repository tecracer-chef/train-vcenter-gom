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
| `logger`           | Logger instance                                        | $stdout, info |            |
| `quick`            | Enable quick mode                                      | `false`    |               |
| `shell_type`       | Shell type ("auto", "linux", "cmd", "powershell")      | `auto`     |               |
| `timeout`          | Timeout in seconds                                     | `60`       |               |

By design, Train VSphere GOM requires two authentication steps: One to get access to the VCenter API and one
to get access to the guest VM with local credentials.

VMs can be searched by their IP address, their UUID, their VMware inventory path or by DNS name.

The environment variables are aligned to those from VMware SDK and ESXCLI.

## Quick Mode

In quick mode, non-essential operations are omitted to save time over slow connections.

- no deletion of temporary files (in system temp directory)
- no checking for file existance before trying to read
- only reading standard error, if exit code was not zero

## Limitations

- SSPI based guest VM logins are not supported yet
- using PowerShell via GOM is very slow (7-10 seconds roundtrip)

## Example use

```ruby
require 'train-vsphere-gom'

train  = Train.create('vsphere-gom', {
            # Relying on VI_* variables for VCenter configuration
            host:     '10.20.30.40'
            username: 'Administrator',
            password: 'Password'
         })
conn   = train.connection
conn.run_command("Write-Host 'Inside the VM'")
```

## References

- [vSphere Web Services: GOM](https://code.vmware.com/docs/5722/vsphere-web-services-api-reference/doc/vim.vm.guest.GuestOperationsManager.html)
