#!/usr/bin/bash

# Ubuntu Server Bootstrapper
# by Marcus Nilsson <marcus@bitexclusive.se>
# Licensed under MIT

### Global variables
cert_email=""
cert_domails=""
cert_add="1"

update_system="1"

fw_allow_http="1"
fw_allow_https="1"
fw_enable="1"

ssh_reload="1"

has_errored="0"

backtitle="Ubuntu Server Bootstrapper"

### Functions

### Helper functions
log_if_fail() {
    command="${@:1:$#-1}"

    log=$(eval $command 2>&1)

    if [ "$?" -ne 0 ]; then
        has_errored="1"
        for message; do true; done

        echo "Failed running command: $command" >> usb.log
        echo "$message" >> usb.log
        echo "--- LOG ---" >> usb.log
        echo "$log" >> usb.log
        echo "--- END LOG ---" >> usb.log
        return 1
    fi

    return 0
}

cancelscript() {
    clear
    exit 1
}

errorout() {
	clear;
	echo "ERROR:" >&2
	echo "$1" >&2
	echo "" >&2
	echo "ABORTING" >&2
	exit 1
}

installpkg() {
    # Might scrap the for-loop in a future version
    # since I do think installing everything at once is faster
    # but I want to be explicit about what happens
	for arg in "$@"
	do
		dialog --backtitle "$backtitle" --title "Installing..." --infobox "Installing $arg" 5 70
		log_if_fail apt install -y "$arg" "Failed installing $arg"
	done
}

### Program functions
ui_welcome() {
    dialog --backtitle "$backtitle" --colors --title "Ubuntu Server Bootstrapper" --yes-label "Continue" --no-label "Cancel" --yesno "This script will install and configure NGINX, MariaDB, Redis, Composer, nodejs, npm, ufw, Certbot(Let's Encrypt), fail2ban and PHP.\nConfigurations are mostly for Laravel.\n\nWARNING:\nIf you are using ssh on something other than port 22, you risk getting booted off!\n\nDo you wish to continue?" 15 70 || cancelscript
}

ui_final() {
    if [ "$has_errored" -eq 0 ]; then
        dialog --backtitle "$backtitle" --colors --title "Done" --ok-label "Exit" --msgbox "Everything has been installed and set up succesfully! Have fun!" 5 70
        dialog --backtitle "$backtitle" --colors --title "Final Step" --yesno "Do you want to run mysql_secure_installation now?" && mysql_secure_installation
    else
        dialog --backtitle "$backtitle" --colors --title "Done" --ok-label "Exit" --msgbox "Installation has finnished but with some failiures, log can be found at $(pwd)/usb.log!" 10 70
        dialog --backtitle "$backtitle" --colors --title "Final Step" --yesno "Do you want to run mysql_secure_installation now?" && mysql_secure_installation
    fi

    cancelscript
}

ui_update_system() {
    dialog --backtitle "$backtitle" --colors --title "Update system?" --yesno "Do you want to update your system?" 5 70
    update_system="$?"
}

ui_run_ssh_keys() {

    # Number of users
    nusers=$(ls -la /home | tail -n +4 | wc -l)

    # See if there are any users available
    if [ $nusers -eq 0 ]; then
        dialog --backtitle "$backtitle" --title "Something went wrong!" --infobox "There are no users in /home. Aborting!" 15 70
        sleep 5
        return
    fi

    # Get all users with at home folder
    users=$(ls -la /home | awk '{ print NR-3,$9; }' | tail -n +4 | sed ':a; N; $!ba; s/\n/ /g')

    # Get userid
    userid=$(dialog --backtitle "$backtitle" --colors --title "Which user" --menu "Select user:" 15 30 "$nusers" $users 2>&1 >/dev/tty)

    if [ $? -ne 0 ]; then
        return
    fi
    
    #find username from id
    username=$(echo "$users" | awk -v i=$userid '{ pos = i * 2; print $(pos); }')

    url=$(dialog --backtitle "$backtitle" --colors --title "URL to key" --inputbox "URL to Public key:" 5 70 2>&1 >/dev/tty)

    dialog --backtitle "$backtitle" --colors --title "Add key?" --yesno "Do you want to add the key from $url to user $username's authorized_keys?" 15 70

    if [ $? -ne 0 ]; then
        dialog --backtitle "$backtitle" --colors --title "Another user?" --yesno "Do you want to add another user instead? " 10 70

        if [ $? -ne 0 ]; then
            return
        else
            addkeytouser
        fi
    else
		dialog --backtitle "$backtitle" --title "Downloading and adding key" --infobox "Downloading and adding key from $url to user $username's authorized_keys" 15 70

        log_if_fail wget "$url" -O /tmp/downloaded_public_key "Failed download public key from $url"

        if [ $? -ne 0 ]; then
		    dialog --backtitle "$backtitle" --title "Something went wrong!" --infobox "Something when wrong when downloading public key. Aborting!" 15 70
            sleep 5
            return
        fi

        mkdir -p "/home/$username/.ssh" >/dev/null 2>&1;
        touch "/home/$username/.ssh/authorized_keys" >/dev/null 2>&1;
        cat /tmp/downloaded_public_key >> "/home/$username/.ssh/authorized_keys"

        # Change ownership and permissions incase the folder/file didn't
        # exist before running this program
        chown -R "$username:$username" "/home/$username/.ssh" >/dev/null 2>&1;
        chmod 700 "/home/$username/.ssh" >/dev/null 2>&1;
        chmod 600 "/home/$username/.ssh/authorized_keys" >/dev/null 2>&1;

        dialog --backtitle "$backtitle" --colors --title "One more user?" --yesno "Do you want to add a key to one more user?" 10 70

        if [ $? -ne 0 ]; then
            return
        else
            addkeytouser
        fi
    fi
}

ui_reload_ssh() {
    dialog --backtitle "$backtitle" --colors --title "Restart SSH?" --yesno "Do you want to restart ssh?\n\nWARNING:\nIf you haven't copied your public key you WILL get locked out because the current ssh config is not allowing root nor password login!" 5 70
    ssh_reload="$?"
}

ui_fw() {
    dialog --backtitle "$backtitle" --colors --title "Firewall" --yesno "Allow HTTP?" 5 70
    fw_allow_http="$?"
    dialog --backtitle "$backtitle" --colors --title "Firewall" --yesno "Allow HTTPS?" 5 70
    fw_allow_https="$?"
    dialog --backtitle "$backtitle" --colors --title "Enable Firewall?" --yesno "Do you want to enable ufw(firewall)?\n\nWARNING:\nIf you have changed ssh port from port 22 and didn't restart ssh in the question before, you WILL get booted off!" 5 70
    fw_enable="$?"
}

ui_create_certificate() {
    dialog --backtitle "$backtitle" --colors --title "Create certificate" --yesno "Do you want to create a Let's Encrypt certificate for your website now?" 15 70

    if [ "$?" -ne 0 ]; then
        cert_add="1"
        return
    fi

    cert_email=$(dialog --backtitle "$backtitle" --colors --title "Create certificate" --inputbox "Email address:" 5 70 2>&1 >/dev/tty)
    cert_domains=$(dialog --backtitle "$backtitle" --colors --title "Create certificate" --inputbox "Domains (comma separated):" 15 70 2>&1 >/dev/tty)
    cert_add="0"
}

run_update() {
    if [ "$update_system" -ne 0 ]; then
        return
    fi

	dialog --backtitle "$backtitle" --title "Updating the system..." --infobox "Updating the system" 5 70
	apt update -y >/dev/null 2>&1 || errorout "System update failed"
	apt upgrade -y >/dev/null 2>&1 || errorout "System upgrade failed"
}

run_install_main() {
    installpkg nginx mariadb redis-server ufw fail2ban php openssh-server
}

run_install_dependencies() {
    installpkg zip unzip php-fpm php-mysql php-mbstring php-dom php-redis php-dev php-pear php-gd
}

run_install_composer() {
    dialog --backtitle "$backtitle" --title "Installing..." --infobox "Installing Composer" 5 70
    log_if_fail "curl -sS https://getcomposer.org/installer | php" "Failed when installing composer"
    log_if_fail mv composer.phar /usr/local/bin/composer "Failed when moving composer"
    log_if_fail chmod +x /usr/local/bin/composer "Failed when marking composer exacutable"
}

run_install_certbot() {
    # Uninstalling certbot from apt if it exists
    dialog --backtitle "$backtitle" --colors --title "Uninstalling..." --infobox "Uninstalling old Certbot (if any exists)" 5 70
    log_if_fail apt remove certbot -y "Failed when removing old certbot";

    # Install snap for certbot
    installpkg snap
    log_if_fail snap install core "Failed when installing core from snap"
    log_if_fail snap refresh core "Failed when refreshing core from snap";

    dialog --backtitle "$backtitle" --colors --title "Installing..." --infobox "Installing Certbot" 5 70
    log_if_fail snap install --classic certbot "Failed when installing classic certbot from snap"
    if [ -f /usr/bin/certbot ]; then
        log_if_fail rm /usr/bin/certbot "Failed removing already existing /usr/bin/certbot"
    fi
    log_if_fail ln -s /snap/bin/certbot /usr/bin/certbot "Failed when linking certbot"
}

run_install_nodejs() {
    installpkg nodejs npm

    log_if_fail npm cache clean -f "Failed cleaning npm cache"
    log_if_fail npm install -g n "Failed installing npm package n"
    log_if_fail n stable "Failed cleaning npm cache"
}

run_config_nginx() {
    dialog --backtitle "$backtitle" --title "Configuring..." --infobox "Configuring nginx" 5 70

cat <<EOF > /etc/nginx/sites-available/default
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    root /var/www/public;
    
    index index.php index.html index.htm index.nginx-debian.html;
    
    charset utf-8;
    
    server_name _;
    
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    
    error_page 404 /index.php;
    
    location ~ \.php\$ { 
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php7.4-fpm.sock;
    }
}
EOF

    # move from html to public since laravel uses public
    # but if user is going to use that folderpath
    # and use git, they will probably 
    if [ -d /var/www/html ]; then
        log_if_fail mv /var/www/html /var/www/public "Failed moving /var/www/html to /var/www/public"
    else 
        log_if_fail mkdir -p /var/www/public "Failed making directory /var/www/public"
    fi

    # Create a simple php file to validate
    # if the server is up and runing well
cat <<EOFPHP > /var/www/public/index.php
<?php

phpinfo();
EOFPHP

    log_if_fail chown -R www-data:www-data /var/www "Failed when changing ownership of /var/www"

    # Restart NGINX and Postgresql. Enable fail2ban
    dialog --backtitle "$backtitle" --colors --title "Restarting NGINX" --infobox "Restarting NGINX" 5 70
    log_if_fail systemctl restart nginx "Failed when restarting nginx"
}

run_config_fail2ban() {
    dialog --backtitle "$backtitle" --colors --title "Enabling fail2ban" --infobox "Enabling fail2ban" 5 70
    log_if_fail systemctl enable fail2ban "Failed enabling fail2ban"
    log_if_fail systemctl start fail2ban "Failed starting fail2ban"
}

run_config_pgsql() {
    dialog --backtitle "$backtitle" --colors --title "Restarting Postgresql" --infobox "Restarting Postgresql" 5 70
    log_if_fail systemctl restart postgresql "Failed restarting postgresql"
}

run_config_ssh() {
    dialog --backtitle "$backtitle" --title "Configuring..." --infobox "Configuring ssh" 5 70
    cat <<EOF > /etc/ssh/sshd_config
Include /etc/ssh/sshd_config.d/*.conf
PermitRootLogin no
ChallengeResponseAuthentication no
UsePAM no
X11Forwarding yes
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp  /usr/lib/openssh/sftp-server
PasswordAuthentication no
EOF

    if [ "$ssh_reload" -eq 0 ]; then 
        log_if_fail systemctl restart ssh "Failed restarting ssh"
    fi
}

run_config_fw() {
    log_if_fail ufw allow ssh "Failed when allowing ssh";

    # FORGIVE ME GOD FOR I HAVE SINED WITH THESE NESTED IF-STATMENTS
    # If allow ssh failed
    if [ "$?" -ne 0 ]; then
        # Add ssh is set to reload
        if [ "$ssh_reload" -eq 0 ]; then
            # And firewall will get enabled
            if [ "$fw_enable" -eq 0 ]; then
                errorout "Failed when allowing ssh port 22 firewall, and ssh and ufw will get enabled and reloaded. Exiting to prevent loosing access to server! log can be found at $(pwd)/usb.log"
            fi
        fi
    fi

    if [ "$fw_allow_http" -eq 0 ]; then 
        log_if_fail ufw allow http "Failed allowing http"
    fi

    if [ "$fw_allow_https" -eq 0 ]; then 
        log_if_fail ufw allow https "Failed allowing https"
    fi
    if [ "$fw_enable" -eq 0 ]; then 
        log_if_fail "yes | ufw enable" "Failed enabling firewall (ufw)"
    fi
}

run_config_certbot() {
    if [ "$cert_add" -eq 0 ]; then
        dialog --backtitle "$backtitle" --colors --title "Create certificate" --infobox "Registering $domains with email $email" 15 70
        log_if_fail certbot --nginx --agree-tos -m "$cert_email" -d "$cert_domains" "Failed creating certificate for $domains with email $email"

        if [ $? -ne 0 ]; then
            dialog --backtitle "$backtitle" --colors --title "Registration failed" --msgbox "Creating certificate failed.\n\nLogs can be found at $(pwd)/usb.log" 15 70
        else
            dialog --backtitle "$backtitle" --colors --title "Registration succeded" --msgbox "Certification has been succesfully completed." 15 70
        fi
    fi
}

### Main Program

apt install -y dialog || errorout "Are you root and running on Ubuntu?"

ui_welcome
ui_update_system


ui_fw
ui_reload_ssh

dialog --backtitle "$backtitle" --colors --title "Add public key?" --yesno "Do you want to add public keys to users?\n\nWARNING:\nIf you don't do this and don't have a public key already added, you risk getting locked out if you press yes on restarting ssh!\n\nNOTE:\nThey must have a folder in /home and a group with the same name must exist." 15 70

if [ "$?" -eq 0 ]; then 
    ui_run_ssh_keys
fi

ui_create_certificate

dialog --backtitle "$backtitle" --colors --title "Setup starting" --infobox "Installation and configuration will start shortly, this may take several minutes/hours!" 15 70; sleep 5

run_update
run_install_main
run_install_dependencies
run_install_composer
run_install_certbot
run_install_nodejs

run_config_nginx
run_config_fail2ban
run_config_pgsql
run_config_ssh
run_config_fw
run_config_certbot

ui_final
