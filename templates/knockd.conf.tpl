[options]
    UseSyslog
    Interface = __IFACE__

[openSSH]
    sequence      = __OPEN_SEQ__
    seq_timeout   = 10
    command       = /usr/bin/firewall-cmd --zone=public --add-rich-rule='rule family="ipv4" source address="%IP%" port port="22" protocol="tcp" accept' --timeout=60
    tcpflags      = syn

[closeSSH]
    sequence      = __CLOSE_SEQ__
    seq_timeout   = 10
    command       = /usr/bin/firewall-cmd --zone=public --remove-rich-rule='rule family="ipv4" source address="%IP%" port port="22" protocol="tcp" accept'
    tcpflags      = syn
