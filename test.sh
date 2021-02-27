#!/usr/bin/bash
# This is just a little file where i try out some stuff then add them to the main file

addkeytouser() {

    # Number of users
    nusers=$(ls -la /home | tail -n +4 | wc -l)

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
        chown -R "$username:$username" "/home/$username/.ssh/authorized_keys" >/dev/null 2>&1;
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

addkeytouser

# dialog --colors --title "Add public key?" --yesno "Do you want to add public keys to users?\n\nWARNING:\nIf you don't do this and don't have a public key already added, you risk getting locked out if you press yes on restarting ssh!\n\nNOTE:\nThey must have a folder in /home and a group with the same name must exist." 15 70 && addkeytouser

# username="www-data"

# chown -R "$username:$username" "/home/$username/.ssh/authorized_keys"
# chmod 700 "/home/$username/.ssh"
# chmod 600 "/home/$username/.ssh/authorized_keys"
