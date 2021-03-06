#!/bin/bash


Dovecot_Conf()
{
	sed -i '/^mail_location =.*/s/^/#/g' /etc/dovecot/conf.d/10-mail.conf 
	echo "mail_location = maildir:/var/mail/vhosts/%d/%n" >> /etc/dovecot/conf.d/10-mail.conf

	mkdir -p /etc/dovecot
	touch /etc/dovecot/users
	
	sed -i '/\!include auth-system\.conf\.ext/s/^/#/g' /etc/dovecot/conf.d/10-auth.conf
	sed -i '/\!include auth-passwdfile\.conf\.ext/s/^#//g' /etc/dovecot/conf.d/10-auth.conf

	sed -i '/^mail_privileged_group =.*/s/^/#/g' /etc/dovecot/conf.d/10-mail.conf
	echo "mail_privileged_group = mail" >> /etc/dovecot/conf.d/10-mail.conf

	sed -i '/^disable_plaintext_auth =.*/s/^/#/g' /etc/dovecot/conf.d/10-auth.conf
	echo "disable_plaintext_auth = no" >> /etc/dovecot/conf.d/10-auth.conf

	sed -i '/^auth_mechanisms =.*/s/^/#/g' /etc/dovecot/conf.d/10-auth.conf
	echo "auth_mechanisms = plain login" >> /etc/dovecot/conf.d/10-auth.conf

	sed -i '/^protocols =.*/s/^/#/g' /etc/dovecot/dovecot.conf
	echo "protocols = imap pop3 lmtp" >> /etc/dovecot/dovecot.conf

	sed -i '/^listen =.*/s/^/#/g' /etc/dovecot/dovecot.conf
	echo "listen = *" >> /etc/dovecot/dovecot.conf

	
	sed -i '/^ssl =.*/s/^/#/g' /etc/dovecot/conf.d/10-ssl.conf
	echo "ssl = no" >> /etc/dovecot/conf.d/10-ssl.conf

	
	sed -i '/^ssl =.*/s/^/#/g' /etc/dovecot/conf.d/10-logging.conf
	echo "log_path = /var/log/dovecot.log" >> /etc/dovecot/conf.d/10-logging.conf
	
	
cat >>"/etc/dovecot/conf.d/10-mail.conf"<<EOF
	passdb {
	  driver = passwd-file
	  args = username_format=%u /etc/dovecot/users
	}
	userdb {
	  driver = static
	  args = uid=vmail gid=vmail home=/var/mail/vhosts/%d/%n
	}
EOF

	
cat >"/etc/dovecot/conf.d/10-master.conf"<<EOF
#default_process_limit = 100
#default_client_limit = 1000

# Default VSZ (virtual memory size) limit for service processes. This is mainly
# intended to catch and kill processes that leak memory before they eat up
# everything.
#default_vsz_limit = 256M

# Login user is internally used by login processes. This is the most untrusted
# user in Dovecot system. It shouldn't have access to anything at all.
#default_login_user = dovenull

# Internal user is used by unprivileged processes. It should be separate from
# login user, so that login processes can't disturb other processes.
#default_internal_user = dovecot

service imap-login {
  inet_listener imap {
    #port = 143
  }
  inet_listener imaps {
    #port = 993
    #ssl = yes
  }

  # Number of connections to handle before starting a new process. Typically
  # the only useful values are 0 (unlimited) or 1. 1 is more secure, but 0
  # is faster. <doc/wiki/LoginProcess.txt>
  #service_count = 1

  # Number of processes to always keep waiting for more connections.
  #process_min_avail = 0

  # If you set service_count=0, you probably need to grow this.
  #vsz_limit = 
}

service pop3-login {
  inet_listener pop3 {
    #port = 110
  }
  inet_listener pop3s {
    #port = 995
    #ssl = yes
  }
}

service lmtp {
  unix_listener lmtp {
    mode = 0666
    user = postfix
    group = postfix
  }

  # Create inet listener only if you can't use the above UNIX socket
  #inet_listener lmtp {
    # Avoid making LMTP visible for the entire internet
    #address =
    #port = 
  #}
}

service imap {
  # Most of the memory goes to mmap()ing files. You may need to increase this
  # limit if you have huge mailboxes.
  #vsz_limit = 

  # Max. number of IMAP processes (connections)
  #process_limit = 1024
}

service pop3 {
  # Max. number of POP3 processes (connections)
  #process_limit = 1024
}

service auth {
  # auth_socket_path points to this userdb socket by default. It's typically
  # used by dovecot-lda, doveadm, possibly imap process, etc. Users that have
  # full permissions to this socket are able to get a list of all usernames and
  # get the results of everyone's userdb lookups.
  #
  # The default 0666 mode allows anyone to connect to the socket, but the
  # userdb lookups will succeed only if the userdb returns an "uid" field that
  # matches the caller process's UID. Also if caller's uid or gid matches the
  # socket's uid or gid the lookup succeeds. Anything else causes a failure.
  #
  # To give the caller full permissions to lookup all users, set the mode to
  # something else than 0666 and Dovecot lets the kernel enforce the
  # permissions (e.g. 0777 allows everyone full permissions).
  unix_listener auth-userdb {
    mode = 0666
    user = vmail 
    #group = 
  }

  # Postfix smtp-auth
  unix_listener /var/spool/postfix/private/auth {
    mode = 0666
    user = postfix
    group = postfix
  }

  # Auth process is run as this user.
  #user = 
}

service auth-worker {
  # Auth worker process is run as root by default, so that it can access
  # /etc/shadow. If this isn't necessary, the user should be changed to
  # .
  #user = root
}

service dict {
  # If dict proxy is used, mail processes should have access to its socket.
  # For example: mode=0660, group=vmail and global mail_access_groups=vmail
  unix_listener dict {
    #mode = 0600
    #user = 
    #group = 
  }
}
EOF

}


Postfix_Conf(){
	postconf -e myhostname=$subDomain.$domain
	postconf -e mydomain=$domain
	postconf -e myorigin='$mydomain'
	postconf -e inet_protocols=ipv4
	postconf -e inet_interfaces=all
	postconf -e mydestination=localhost
	
	touch /etc/postfix/virtual_mailbox_map
	#echo $username@$domain $domain/$username/ >> /etc/postfix/virtual_mailbox_map
	postmap /etc/postfix/virtual_mailbox_map
	
	#forward email
	postconf virtual_alias_maps=hash:/etc/postfix/virtual
	postmap /etc/postfix/virtual_mailbox_map
	postmap /etc/postfix/virtual

	mkdir -p /var/mail/vhosts

	postconf virtual_mailbox_domains=$domain
	postconf virtual_mailbox_base=/var/mail/vhosts
	postconf virtual_mailbox_maps=hash:/etc/postfix/virtual_mailbox_map
	postconf virtual_minimum_uid=100
	postconf virtual_uid_maps=static:5000
	postconf virtual_gid_maps=static:5000


	groupadd -g 5000 vmail
	useradd -g vmail -u 5000 vmail -d /var/mail

	mkdir -p  /var/mail/vhosts/$domain/$username

	chown -R vmail:vmail /var/mail
	chown -R vmail:vmail /var/mail/*

	postconf -e smtpd_sasl_type=dovecot
	postconf -e smtpd_sasl_path=private/auth
	postconf -e smtpd_sasl_auth_enable=yes
	postconf -e smtpd_sasl_security_options=noanonymous
	postconf -e smtpd_sasl_local_domain='$myhostname'
	postconf -e smtpd_recipient_restrictions="permit_sasl_authenticated, permit_mynetworks, reject_unauth_destination"

	postconf bounce_queue_lifetime=300s
	postconf broken_sasl_auth_clients=yes
	postconf maximal_queue_lifetime=300s
	postconf maximal_backoff_time=300s
	
	Dovecot_Conf
}



    domain="google.com"
    subDomain="mail"
    
    
	setenforce 0
	getenforce
	sed -i 's/enforcing/disabled/g' /etc/selinux/config
	systemctl stop firewalld.service
	systemctl disable firewalld.service
	firewall-cmd --state
	
	yum remove sendmail
	yum -y install epel-release postfix dovecot
	
	Postfix_Conf




systemctl start postfix && systemctl enable postfix
systemctl start dovecot && systemctl enable dovecot

netstat -anlpt

