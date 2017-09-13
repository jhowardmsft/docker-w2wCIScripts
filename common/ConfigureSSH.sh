#!/bin/bash
logfile=/cygdrive/c/packer/ConfigureSSH.log
exec >> $logfile
echo ConfigureSSH.sh running as `whoami`  # Should NOT be system!
cygrunsrv --stop sshd > /dev/nul 2>&1
cygrunsrv --remove sshd > /dev/nul 2>&1
net user sshd /delete> /dev/nul 2>&1
net user cyg_server /delete > /dev/nul 2>&1
rm -r /etc/ssh* /var/empty /var/log/sshd.log /var/log/lastlog /etc/passwd ~/.ssh > /dev/nul 2>&1
mkdir ~/.ssh
/usr/bin/ssh-host-config -y -w `openssl rand -base64 32` -c "binmode ntsec"
echo "PasswordAuthentication no" >> /etc/sshd_config
echo "ClientAliveInterval 15" >> /etc/sshd_config
chmod 700 ~/.ssh
cp /cygdrive/c/packer/authorized_keys ~/.ssh/authorized_keys
chmod 644 ~/.ssh/authorized_keys
#/usr/bin/cygrunsrv -S sshd  Start on next reboot
