text
version=DEVEL
keyboard --vckeymap=us --xlayouts='us'
lang en_US.UTF-8
timezone UTC

bootloader --location=mbr
clearpart --all --initlabel
autopart --type=plain
network --bootproto=dhcp --device=link --activate

%pre --interpreter=/usr/bin/bash
/usr/bin/ask-url.sh
%end

%include /tmp/bootc-target.ks
reboot
