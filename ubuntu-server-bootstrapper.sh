#!/usr/bin/bash

# Ubuntu Server Bootstrapper
# by Marcus Nilsson <marcus@bitexclusive.se>
# Licensed under MIT

### Functions ###
errorout() {
	clear;
	echo "ERROR:" >&2
	echo "$1" >&2
	echo "" >&2
	echo "ABORTING" >&2
	exit 1
}

updatesystem() {
	dialog --title "Updating the system..." --infobox "Updating the system" 5 70
	apt update -y >/dev/null 2>&1 || errorout "System update failed"
	apt upgrade -y >/dev/null 2>&1 || errorout "System upgrade failed"
}

installpkg() {
    # Might scrap the for-loop in a future version
    # since I do think installing everything at once is faster
    # but I want to be explicit about what happens
	for arg in "$@"
	do
		dialog --title "Installing..." --infobox "Installing $arg" 5 70
		apt install -y "$arg" >/dev/null 2>&1;
	done
}

# create certificate with certbot
certifywithcertbot() {
    dialog --colors --title "Create certificate" --yesno "Certbot is installed, do you want to create a certificate for your website now?" 15 70 || return

    email=$(dialog --colors --title "Create certificate" --inputbox "Email address:" 5 70 2>&1 >/dev/tty)
    domains=$(dialog --colors --title "Create certificate" --inputbox "Domains (comma separated):" 15 70 2>&1 >/dev/tty)

    dialog --colors --title "Create certificate" --infobox "Registering $domains with email $email" 15 70
    certbot --nginx --agree-tos -m "$email" -d "$domains" > certbot.log 2> certbot-error.log

    if [ $? -ne 0 ]; then
        dialog --colors --title "Registration failed" --msgbox "Creating certificate failed.\n\nLogs can be found at $(pwd)/certbot.log and $(pwd)/certbot-error.log" 15 70
    else
        dialog --colors --title "Registration succeded" --msgbox "Certification has been succesfully completed.\n\nLog can be found at $(pwd)/certbot.log" 15 70
        rm certbot-error.log 
    fi
}

# Add public key to users 
addkeytouser() {
    # Number of users
    nusers=$(ls -la /home | tail -n +4 | wc -l)

    # See if there are any users available
    if [ $nusers -e 0 ]; then
        dialog --title "Something went wrong!" --infobox "There are no users in /home. Aborting!" 15 70
        sleep 5
        return
    fi

    # Get all users with at home folder
    users=$(ls -la /home | awk '{ print NR-3,$9; }' | tail -n +4 | sed ':a; N; $!ba; s/\n/ /g')

    # Get userid
    userid=$(dialog --colors --title "Which user" --menu "Select user:" 15 30 "$nusers" $users 2>&1 >/dev/tty)

    if [ $? -ne 0 ]; then
        return
    fi
    
    #find username from id
    username=$(echo "$users" | awk -v i=$userid '{ pos = i * 2; print $(pos); }')

    url=$(dialog --colors --title "URL to key" --inputbox "URL to Public key:" 5 70 2>&1 >/dev/tty)

    dialog --colors --title "Add key?" --yesno "Do you want to add the key from $url to user $username's authorized_keys?" 15 70

    if [ $? -ne 0 ]; then
        dialog --colors --title "Another user?" --yesno "Do you want to add another user instead? " 10 70

        if [ $? -ne 0 ]; then
            return
        else
            addkeytouser
        fi
    else
		dialog --title "Downloading and adding key" --infobox "Downloading and adding key from $url to user $username's authorized_keys" 15 70

        wget "$url" -O /tmp/downloaded_public_key >/dev/null 2>&1;

        if [ $? -ne 0 ]; then
		    dialog --title "Something went wrong!" --infobox "Something when wrong when downloading public key. Aborting!" 15 70
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

        dialog --colors --title "One more user?" --yesno "Do you want to add a key to one more user?" 10 70

        if [ $? -ne 0 ]; then
            return
        else
            addkeytouser
        fi
    fi


}

cancelscript() {
    clear
    exit 1
}

### Start of Program ###

# Download dialog to check if they are root
apt install -y dialog || errorout "Are you root and running on Ubuntu?"

# Welcome user
dialog --colors --title "Ubuntu Server Bootstrapper" --yes-label "Continue" --no-label "Cancel" --yesno "This script will install and configure NGINX, Postgresql, Redis, Composer, ufw, Certbot(Let's Encrypt), fail2ban and PHP.\nConfigurations are mostly for Laravel.\n\nWARNING:\nIf you are using ssh on something other than port 22, you risk getting booted off!\n\nDo you wish to continue?" 15 70 || cancelscript

# Ask you if they want to update the system
dialog --colors --title "Update system?" --yesno "Do you want to update your system?" 5 70 && updatesystem

# Install dependencies
installpkg zip unzip

# Install nginx and postgresql
installpkg nginx postgresql postgresql-contrib redis-server ufw fail2ban php nodejs npm openssh-server

# Install composer
dialog --title "Installing..." --infobox "Installing Composer" 5 70
# curl -sS https://getcomposer.org/installer | php >/dev/null 2>$1
wget "https://getcomposer.org/installer" -o composer-installer.php
php composer-installer.php >/dev/null 2>$1
rm composer-installer.php
mv composer.phar /usr/local/bin/composer
chmod +x /usr/local/bin/composer

# installing php dependencies
installpkg php-fpm php-pgsql php-mbstring php-dom php-redis php-dev php-pear php-gd

# Configure nginx
dialog --title "Configuring..." --infobox "Configuring nginx" 5 70
cat <<EOF > /etc/nginx/sites-available/default
server {
	listen 80 default_server;
	listen [::]:80 default_server;
	
	root /var/www/public;
	
	index index.php index.html index.htm index.nginx-debian.html;
	
	charset utf-8;
	
	server_name _;
	
	location / {
		try_files $uri $uri/ /index.php?$query_string;
	}
	
	error_page 404 /index.php;
	
	location ~ \.php$ { 
		include snippets/fastcgi-php.conf;
		fastcgi_pass unix:/var/run/php/php7.4-fpm.sock;
	}
}
EOF
clear

# Uninstalling certbot from apt if it exists
dialog --colors --title "Uninstalling..." --infobox "Uninstalling old Certbot (if any exists)" 5 70
apt remove certbot >/dev/null 2>&1;

# Install snap for certbot
installpkg snap
snap install core >/dev/null 2>&1;
snap refresh core >/dev/null 2>&1;

dialog --colors --title "Installing..." --infobox "Installing Certbot" 5 70
snap install --classic certbot >/dev/null 2>&1;
ln -s /snap/bin/certbot /usr/bin/certbot
certifywithcertbot

# Configuring ssh and ufw
dialog --colors --title "Allowing SSH" --infobox "Allowing Post 22 (SSH)" 5 70
ufw allow ssh >/dev/null 2>&1;
sleep 1

dialog --colors --title "Firewall" --yesno "Allow HTTP?" 5 70 &&  ufw allow http >/dev/null 2>$1
dialog --colors --title "Firewall" --yesno "Allow HTTPS?" 5 70 &&  ufw allow https >/dev/null 2>$1


dialog --title "Configuring..." --infobox "Configuring nginx" 5 70
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

# move from html to public since laravel uses public
# but if user is going to use that folderpath
# and use git, they will probably 
mv /var/www/html /var/www/public >/dev/null 2>$1

# Create a simple php file to validate
# if the server is up and runing well
cat <<EOF > /var/www/public/index.php
<?php

phpinfo();
EOF

chown -R www-data:www-data /var/www

# Restart NGINX and Postgresql. Enable fail2ban
dialog --colors --title "Restarting NGINX" --infobox "Restarting NGINX" 5 70
systemctl restart nginx >/dev/null 2>$1


dialog --colors --title "Restarting Postgresql" --infobox "Restarting Postgresql" 5 70
systemctl restart postgresql >/dev/null 2>$1

dialog --colors --title "Enabling fail2ban" --infobox "Enabling fail2ban" 5 70
systemctl enable fail2ban >/dev/null 2>$1
systemctl start fail2ban >/dev/null 2>$1


# Is this really required?
dialog --colors --title "Enabling php-redis" --infobox "Enabling php-redis" 5 70
phpenmod redis

# Ask user if they want to add public keys
dialog --colors --title "Add public key?" --yesno "Do you want to add public keys to users?\n\nWARNING:\nIf you don't do this and don't have a public key already added, you risk getting locked out if you press yes on restarting ssh!\n\nNOTE:\nThey must have a folder in /home and a group with the same name must exist." 15 70 && addkeytouser

# Ask to enable ssh
dialog --colors --title "Restart SSH?" --yesno "Do you want to restart ssh?\n\nWARNING:\nIf you haven't copied your public key you WILL get locked out because the current ssh config is not allowing root nor password login!" 5 70 && systemctl restart ssh >/dev/null 2>$1

# Ask to enable firewall (ufw)
dialog --colors --title "Enable Firewall?" --yesno "Do you want to enable ufw(firewall)?\n\nWARNING:\nIf you have changed ssh port from port 22 and didn't restart ssh in the question before, you WILL get booted off!" 5 70 && yes | ufw enable >/dev/null 2>$1

dialog --colors --title "Done" --ok-label "Exit" --msgbox "Everything has been installed and set up now! Have fun!" 5 70
clear
