#!/bin/sh
# add a SSH key for the cluster if no authorized_keys file exists in $HOME/.ssh
if [ $UID -lt 500 -a $UID -ne 0 ]; then
    exit
fi
if [ ! -f "$HOME/.ssh/authorized_keys" -a ! -f "$HOME/.ssh/id_ed25519" ]; then
    echo "Configuring SSH for cluster access"
    ssh-keygen -o -a 100 -t ed25519 -f $HOME/.ssh/id_ed25519 -N '' -C "$USER@$HOSTNAME cluster key" > /dev/null 2>&1
    cat $HOME/.ssh/id_ed25519.pub >> $HOME/.ssh/authorized_keys
    chmod 0600 $HOME/.ssh/authorized_keys
fi
