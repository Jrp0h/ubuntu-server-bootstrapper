#!/usr/bin/bash
# This is just a little file where i try out some stuff then add them to the main file
has_errored="0"

log_if_fail() {
    command="${@:1:$#-1}"

    log=$(eval $command 2>&1)
    # log=$(yes | ufw enable 2>&1)


    if [ "$?" -ne 0 ]; then
        has_errored="$?"
        for message; do true; done

        echo "Failed running command: $command" >> usb.log
        echo "$message" >> usb.log
        echo "--- LOG ---" >> usb.log
        echo "$log" >> usb.log
        echo "--- END LOG ---" >> usb.log
        return 1
    fi
}

# yes | ufw enable

# log_if_fail "YEEE" "YEEET"

# log_if_fail ufw allow http "Failed allowing http"
log_if_fail "yes | ufw enable" "Failed enabling ufw"
# log_if_fail echo  "Hello" "Failed echoing hello"

if [ "$has_errored" -ne 0 ]; then
    echo "it has failed somewhere"
fi
