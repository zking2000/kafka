# Splunk Universal Forwarder Upgrade Playbook

This repository contains Ansible playbooks for upgrading Splunk Universal Forwarder across multiple hosts, with support for Ansible Tower execution.

## Features

- **Automated Upgrade Process**: Complete upgrade workflow with pre/post validation
- **Configuration Backup**: Automatic backup of existing configurations before upgrade
- **Rollback Support**: Quick rollback capability in case of upgrade issues
- **Multi-OS Support**: Compatible with RHEL, CentOS, Ubuntu, and SUSE Linux
- **Ansible Tower Ready**: Designed for enterprise deployment with Ansible Tower
- **Safety Checks**: Pre-upgrade validation and post-upgrade verification
- **Logging**: Comprehensive logging for audit and troubleshooting

## Directory Structure

```
ansible-splunk/
├── upgrade-splunk-forwarder.yml      # Main upgrade playbook
├── rollback-splunk-forwarder.yml     # Rollback playbook
├── inventory.ini                     # Host inventory template
├── ansible.cfg                       # Ansible configuration
├── 使用说明.md                       # Chinese usage guide
├── group_vars/
│   └── all.yml                      # Global variables
├── roles/
│   └── splunk-forwarder-upgrade/    # Upgrade role
│       ├── tasks/main.yml           # Main tasks
│       ├── handlers/main.yml        # Service handlers
│       └── vars/main.yml            # Role variables
└── files/                           # Installation packages directory
    └── README.md                    # Package instructions
```

## Prerequisites

1. **Ansible Control Node**: Ansible 2.9+ installed
2. **Target Hosts**: Linux servers with Splunk Universal Forwarder installed
3. **SSH Access**: Passwordless SSH access to target hosts
4. **Sudo Privileges**: Ansible user must have sudo access
5. **Installation Package**: Splunk UF installation package in `files/` directory

## Quick Start

### 1. Clone and Setup
```bash
git clone <repository-url>
cd ansible-splunk
```

### 2. Configure Inventory
Edit `inventory.ini` and add your Splunk hosts:
```ini
[splunk_forwarders]
splunk-host-01.example.com ansible_host=192.168.1.10
splunk-host-02.example.com ansible_host=192.168.1.11
```

### 3. Download Installation Package
Place the Splunk Universal Forwarder package in the `files/` directory:
```bash
# Example filename
files/splunkforwarder-9.1.2-b6b9c8185839-Linux-x86_64.tgz
```

### 4. Test Connectivity
```bash
ansible splunk_forwarders -m ping
```

### 5. Run Upgrade
```bash
ansible-playbook upgrade-splunk-forwarder.yml
```

## Configuration

### Key Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `new_version` | "9.1.2" | Target Splunk version |
| `splunk_home` | "/opt/splunkforwarder" | Splunk installation directory |
| `splunk_user` | "splunk" | Splunk service user |
| `backup_configs` | true | Create configuration backup |
| `cleanup_temp_files` | true | Clean temporary files after upgrade |

### Customization
Override variables in `group_vars/all.yml` or via command line:
```bash
ansible-playbook upgrade-splunk-forwarder.yml -e "new_version=9.1.3"
```

## Advanced Usage

### Selective Host Upgrade
```bash
# Upgrade specific host
ansible-playbook upgrade-splunk-forwarder.yml -l splunk-host-01

# Upgrade by group
ansible-playbook upgrade-splunk-forwarder.yml -l production_servers
```

### Dry Run
```bash
ansible-playbook upgrade-splunk-forwarder.yml --check --diff
```

### Verbose Output
```bash
ansible-playbook upgrade-splunk-forwarder.yml -vvv
```

## Rollback Procedure

In case of upgrade issues, use the rollback playbook:

```bash
# Interactive rollback (with confirmation)
ansible-playbook rollback-splunk-forwarder.yml

# Automatic rollback (no confirmation)
ansible-playbook rollback-splunk-forwarder.yml -e "auto_confirm=true"
```

## Ansible Tower Configuration

### 1. Create Project
- **Name**: Splunk UF Upgrade
- **SCM Type**: Git
- **SCM URL**: Your repository URL
- **SCM Branch**: main/master

### 2. Create Inventory
- **Name**: Splunk Servers
- **Source**: Manual
- **Hosts**: Import from `inventory.ini`

### 3. Create Credentials
- **Type**: Machine
- **Username**: Your SSH user
- **SSH Private Key**: Upload your private key

### 4. Create Job Template
- **Name**: Splunk UF Upgrade
- **Job Type**: Run
- **Inventory**: Splunk Servers
- **Project**: Splunk UF Upgrade
- **Playbook**: upgrade-splunk-forwarder.yml
- **Credentials**: Select your machine credential

### 5. Optional: Survey Variables
Add survey to make variables configurable:
- `new_version`: Target version
- `backup_configs`: Enable backup (checkbox)

## Upgrade Process Flow

1. **Pre-upgrade Checks**
   - Verify host connectivity
   - Check current Splunk version
   - Validate service status

2. **Upgrade Execution**
   - Stop Splunk service
   - Backup current configuration
   - Copy and extract new package
   - Update file permissions
   - Start Splunk service

3. **Post-upgrade Validation**
   - Verify new version
   - Check service status
   - Validate forwarder configuration
   - Generate upgrade report

## Safety Features

- **Automatic Backup**: Configuration files backed up before upgrade
- **Service Validation**: Pre and post upgrade service checks
- **Rollback Capability**: Quick restore from backup
- **Error Handling**: Graceful failure handling with detailed error messages
- **Timeout Management**: Configurable timeouts for all operations

## Troubleshooting

### Common Issues

1. **SSH Connection Failures**
   ```bash
   # Test SSH connectivity
   ansible splunk_forwarders -m ping
   
   # Check SSH configuration
   ssh -vvv username@hostname
   ```

2. **Permission Denied**
   ```bash
   # Verify sudo access
   ansible splunk_forwarders -m shell -a "sudo whoami" -b
   ```

3. **Service Start Failures**
   ```bash
   # Check Splunk logs
   tail -f /opt/splunkforwarder/var/log/splunk/splunkd.log
   
   # Verify configuration
   /opt/splunkforwarder/bin/splunk btool check
   ```

### Log Files
- **Ansible Log**: `./ansible.log`
- **Splunk Log**: `/opt/splunkforwarder/var/log/splunk/splunkd.log`

## Best Practices

1. **Test Environment**: Always test upgrades in non-production first
2. **Maintenance Window**: Schedule upgrades during maintenance windows
3. **Backup Verification**: Verify backup integrity before proceeding
4. **Staged Rollout**: Upgrade in batches rather than all at once
5. **Monitoring**: Monitor forwarder connectivity post-upgrade

## Security Considerations

- Use dedicated service accounts for Ansible
- Implement proper SSH key management
- Enable audit logging for all operations
- Review and approve playbook changes
- Use encrypted communication channels

## Support Matrix

| OS Family | Versions | Status |
|-----------|----------|--------|
| RHEL/CentOS | 7, 8, 9 | Supported |
| Ubuntu | 18.04, 20.04, 22.04 | Supported |
| SUSE | 12, 15 | Supported |

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Test your changes thoroughly
4. Submit a pull request

## Support

For support and questions:
1. Check the troubleshooting section
2. Review Ansible and Splunk documentation
3. Create an issue in the repository 