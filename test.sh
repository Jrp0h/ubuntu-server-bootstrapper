#!/usr/bin/bash
# This is just a little file where i try out some stuff then add them to the main file

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

certifywithcertbot
