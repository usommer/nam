#!/bin/bash

# nam.sh V1.0.0
#
# Copyright (c) 2019 NetCon Unternehmensberatung GmbH, netcon-consulting.com
#
# Authors: Marc Dierksen (m.dierksen@netcon-consulting.com)

SSH_CONFIG="$HOME/.ssh/config"
if ! [ -f "$SSH_CONFIG" ]; then
    echo "SSH config '$SSH_CONFIG' does not exist"
    exit 1
fi
DIR_ANSIBLE="$HOME/Nextcloud/ansible"
if ! [ -d "$DIR_ANSIBLE" ]; then
    echo "Ansible directory '$DIR_ANSIBLE' does not exist"
    exit 2
fi
DIR_ROLES="$DIR_ANSIBLE/roles"
if ! [ -d "$DIR_ROLES" ]; then
    echo "Ansible roles directory '$DIR_ROLES' does not exist"
    exit 3
fi
if [[ "$OSTYPE" =~ "darwin" ]]; then
    if ! which gawk &>/dev/null; then
        echo "Please install 'gawk'"
        exit 4
    fi
    if ! which gsed &>/dev/null; then
        echo "Please install 'gsed'"
        exit 5
    fi
    CMD_AWK='gawk'
    CMD_SED='gsed'
else
    CMD_AWK='awk'
    CMD_SED='sed'
fi
FILE_CONFIG="$DIR_ANSIBLE/ansible.cfg"
if ! [ -f "$FILE_CONFIG" ]; then
    echo "Ansible config '$FILE_CONFIG' does not exist"
    exit 6
fi
ANSIBLE_INVENTORY="$(grep '^inventory=' $FILE_CONFIG | $CMD_AWK -F= '{print $2}')"
if [ -z "$ANSIBLE_INVENTORY" ]; then
    echo "Ansible inventory not defined in Ansible config '$FILE_CONFIG'"
    exit 7
fi
DIR_INVENTORY="$DIR_ANSIBLE/$ANSIBLE_INVENTORY"
if ! [ -d "$DIR_INVENTORY" ]; then
    echo "Ansible inventory directory '$DIR_INVENTORY' does not exist"
    exit 8
fi
FILE_FUNCTIONAL="$DIR_INVENTORY/groups"
if ! [ -f "$FILE_FUNCTIONAL" ]; then
    echo "Ansible groups file '$FILE_FUNCTIONAL' does not exist"
    exit 9
fi
FILE_COMPANY="$DIR_INVENTORY/companies"
FILE_HOST="$DIR_INVENTORY/hosts"
if ! [ -f "$FILE_HOST" ]; then
    echo "Ansible hosts file '$FILE_HOST' does not exist"
    exit 10
fi
NAME_PLAYBOOK='site.yml'
FILE_PLAYBOOK="$DIR_ANSIBLE/$NAME_PLAYBOOK"
if ! [ -f "$FILE_PLAYBOOK" ]; then
    echo "Ansible playbook '$FILE_PLAYBOOK' does not exist"
    exit 11
fi
DIALOG='dialog'
if ! which $DIALOG &>/dev/null; then
    echo "Please install '$DIALOG'"
    exit 12
fi
EDITOR='vim'
if ! which $EDITOR &>/dev/null; then
    echo "Please install '$EDITOR'"
    exit 13
fi
TITLE_MAIN='NetCon Ansible Manager'
VERSION_MENU="$(grep '^# nam.sh V' $0 | $CMD_AWK '{print $3}')"

# pause and ask for keypress
# parameters:
# none
# return values:
# none
get_keypress() {
    echo
    read -p 'Press any key to continue.'
}

# get list of inventory host names
# parameters:
# none
# return values:
# list of inventory host names
get_hosts() {
    LIST_HOST="$($CMD_AWK '{print $1}' $FILE_HOST)"
    LIST_HOST+=" $(for FILE_HOST in $(ls $DIR_INVENTORY | grep -v 'hosts' | grep -v 'groups' | grep -v 'companies'); do $CMD_AWK '{print $1}' "$DIR_INVENTORY/$FILE_HOST"; done)"
    echo "$LIST_HOST" | xargs -n 1 | grep -v '^$' | sort
}

# get list of names for functional/company group 
# parameters:
# $1 - group file
# return values:
# list of group names
get_groups() {
    grep '^\[' "$1" | grep -v ':' | $CMD_AWK -F '[\\[\\]]' '{print $2}' | sort
}

# get list of functional group names 
# parameters:
# none
# return values:
# list of functional group names
get_functional() {
    get_groups "$FILE_FUNCTIONAL"
}

# get list of company group names 
# parameters:
# none
# return values:
# list of functional group names
get_company() {
    get_groups "$FILE_COMPANY"
}

# get list of inventory hosts for defined group
# parameters:
# $1 - group name
# $2 - group file
# return values:
# list of inventory hosts
get_group_hosts() {
    LIST_HOST=''
    for HOST_NAME in $($CMD_SED -n "/^\[$1\]\s*$/,/^\[/{/^\[/d; p}" "$2" | grep -v '^$'); do
        if echo "$HOST_NAME" | grep -q '\['; then                
            RANGE_START="$(echo "$HOST_NAME" | $CMD_AWK 'match($0, /\[([0-9]):/, a) {print a[1]}')"
            RANGE_END="$(echo "$HOST_NAME" | $CMD_AWK 'match($0, /:([0-9])\]/, a) {print a[1]}')"
            for NUMBER in $(seq $RANGE_START $RANGE_END); do
                [ -z "$LIST_HOST" ] || LIST_HOST+=','
                LIST_HOST+="$(echo $HOST_NAME | $CMD_SED "s/\[\S\+\]/$NUMBER/")"
            done
        else
            [ -z "$LIST_HOST" ] || LIST_HOST+=','
            LIST_HOST+="$HOST_NAME"
        fi
    done
    echo "$LIST_HOST"
}

# get list of inventory hosts for defined functional group
# parameters:
# $1 - group name
# return values:
# list of inventory hosts
get_functional_hosts() {
    get_group_hosts "$1" "$FILE_FUNCTIONAL"
}

# get list of inventory hosts for defined company group
# parameters:
# $1 - group name
# return values:
# list of inventory hosts
get_company_hosts() {
    get_group_hosts "$1" "$FILE_COMPANY"
}

# get list of groups and associated inventory hosts
# parameters:
# $1 - group file
# return values:
# list of groups and associated inventory hosts
get_group_info() {
    LIST_GROUP=''
    for GROUP_NAME in $(grep '^\[' "$1" | grep -v ':' | $CMD_AWK -F '[\\[\\]]' '{print $2}'); do
        LIST_HOST="$(get_group_hosts $GROUP_NAME $1)"
        LIST_GROUP+=" $GROUP_NAME,$LIST_HOST"
    done
    echo "$LIST_GROUP" | xargs -n 1 | sort
}

# get list of functional groups and associated inventory hosts
# parameters:
# none
# return values:
# list of functional groups and associated inventory hosts
get_functional_info() {
    get_group_info "$FILE_FUNCTIONAL"
}

# get list of company groups and associated inventory hosts
# parameters:
# none
# return values:
# list of company groups and associated inventory hosts
get_company_info() {
    get_group_info "$FILE_COMPANY"
}

# add inventory host to group
# parameters:
# $1 - inventory host name
# $2 - group name
# $3 - group file
# return values:
# none
add_host_group() {
    $CMD_SED -i "/\[$2\]/a $1" "$3"
} 

# add inventory host to functional group
# parameters:
# $1 - inventory host name
# $2 - group name
# return values:
# none
add_host_functional() {
    add_host_group "$1" "$2" "$FILE_FUNCTIONAL"
}

# add inventory host to company group
# parameters:
# $1 - inventory host name
# $2 - group name
# return values:
# none
add_host_company() {
    add_host_group "$1" "$2" "$FILE_COMPANY"
}

# remove inventory host from group
# parameters:
# $1 - inventory host name
# $2 - group name
# $3 - group file
# return values:
# none
remove_host_group() {
    COUNT=0
    FOUND=''
    while read LINE; do
        COUNT="$(expr $COUNT + 1)"
        if echo $LINE | grep -q "^\[$2\]"; then
            FOUND=1
        elif ! [ -z "$FOUND" ] && echo $LINE | grep -q "^$1\s*$"; then
            break
        fi      
    done < "$3"
    $CMD_SED -i "${COUNT}d" "$3"
} 

# remove inventory host from functional group
# parameters:
# $1 - inventory host name
# $2 - group name
# return values:
# none
remove_host_functional() {
    remove_host_group "$1" "$2" "$FILE_FUNCTIONAL"
}

# remove inventory host from company group
# parameters:
# $1 - inventory host name
# $2 - group name
# return values:
# none
remove_host_company() {
    remove_host_group "$1" "$2" "$FILE_COMPANY"
}

# select group in dialog menu that the inventory host is added to
# parameters:
# $1 - inventory host name
# $2 - list of groups
# $3 - group type
# return values:
# none
host_add_group() {
    ARRAY=()
    for GROUP_NAME in $2; do
        ARRAY+=("$GROUP_NAME" "$GROUP_NAME")
    done

    exec 3>&1
    DIALOG_RET=$($DIALOG --clear --backtitle "Manage associated groups" --ok-label 'Add' --cancel-label 'Cancel' --no-tags --menu 'Add group' 0 0 0 "${ARRAY[@]}" 2>&1 1>&3)
    RET_CODE=$?
    exec 3>&-
    [ $RET_CODE = 0 ] && add_host_$3 "$1" "$DIALOG_RET"
}

# show list of groups associated with inventory host in dialog menu with option to add/remove associated groups
# parameters:
# $1 - inventory host name
# $2 - group type
# return values:
# none
host_groups() {
    while true; do
        LIST_INCLUDED=''
        LIST_MISSING=''
        for GROUP_INFO in $(get_$2_info); do
            LIST_HOST="$(echo $GROUP_INFO | $CMD_AWK -F, '{$1=""; print $0}')"
            if echo "$LIST_HOST" | grep -q "$1"; then
                LIST_INCLUDED+=" $(echo $GROUP_INFO | $CMD_AWK -F, '{print $1}')"
            else
                LIST_MISSING+=" $(echo $GROUP_INFO | $CMD_AWK -F, '{print $1}')"
            fi
        done

        if ! [ -z "$LIST_INCLUDED" ]; then
            ARRAY=()
            for GROUP_NAME in $LIST_INCLUDED; do
                ARRAY+=("$GROUP_NAME" "$GROUP_NAME")
            done

            exec 3>&1
            DIALOG_RET=$($DIALOG --clear --backtitle "Manage host" --ok-label 'Remove' --extra-button --extra-label 'Add' --cancel-label 'Back' --no-tags --menu 'Associated groups' 0 0 0 "${ARRAY[@]}" 2>&1 1>&3)
            RET_CODE=$?
            exec 3>&-
            if [ $RET_CODE = 0 ]; then
                remove_host_$2 "$1" "$DIALOG_RET"
            elif [ $RET_CODE = 3 ]; then
                host_add_group "$1" "$LIST_MISSING" "$2"
            else
                break
            fi
        else
            $DIALOG --clear --backtitle "Manage host" --ok-label 'Add' --cancel-label 'Back' --no-tags --menu 'Associated groups' 0 0 0 '' 'No groups'
            RET_CODE=$?
            if [ $RET_CODE = 0 ]; then
                host_add_group "$1" "$LIST_MISSING" "$2"
            else
                break
            fi
        fi
    done
}

# show list of functional groups associated with inventory host in dialog menu with option to add/remove associated groups
# parameters:
# $1 - inventory host name
# return values:
# none
host_functional() {
    host_groups "$1" 'functional'
}

# show list of company groups associated with inventory host in dialog menu with option to add/remove associated groups
# parameters:
# $1 - inventory host name
# return values:
# none
host_company() {
    host_groups "$1" 'company'
}

# edit parameters for inventory host in dialog form
# parameters:
# $1 - inventory host name
# return values:
# none
host_edit() {
    NAME_FILE="$DIR_INVENTORY/$1"
    TESTING=''
    if [ -f "$NAME_FILE" ]; then
        TESTING=1
        HOST_INFO="$(cat $NAME_FILE)"
        HOST_NAME="$(echo $HOST_INFO | $CMD_AWK '{print $1}')"
        HOST_ADDRESS="$(echo "$HOST_INFO" | $CMD_AWK 'match($0, /ansible_host=(\S+)/, a) {print a[1]}')"
        HOST_USER="$(echo "$HOST_INFO" | $CMD_AWK 'match($0, /ansible_user=(\S+)/, a) {print a[1]}')"
        HOST_PORT="$(echo "$HOST_INFO" | $CMD_AWK 'match($0, /ansible_port=(\S+)/, a) {print a[1]}')"
        HOST_PYTHON="$(basename $(echo "$HOST_INFO" | $CMD_AWK 'match($0, /ansible_python_interpreter=(\S+)/, a) {print a[1]}'))"
    else
        HOST_INFO="$(grep "^$1\s*" $FILE_HOST)"
        HOST_NAME="$(echo $HOST_INFO | $CMD_AWK '{print $1}')"
        HOST_PYTHON="$(basename $(echo "$HOST_INFO" | $CMD_AWK 'match($0, /ansible_python_interpreter=(\S+)/, a) {print a[1]}'))"
        HOST_INFO="$($CMD_SED -n "/^Host $HOST_NAME\s*$/,/^Host /p" $SSH_CONFIG)"
        HOST_ADDRESS="$(echo "$HOST_INFO" | $CMD_AWK 'match($0, /HostName (\S+)/, a) {print a[1]}')"
        HOST_USER="$(echo "$HOST_INFO" | $CMD_AWK 'match($0, /User (\S+)/, a) {print a[1]}')"
        HOST_PORT="$(echo "$HOST_INFO" | $CMD_AWK 'match($0, /Port (\S+)/, a) {print a[1]}')"
    fi

    exec 3>&1
    DIALOG_RET=$(dialog --ok-label 'Save' --backtitle 'Manage host'         \
	    --title 'Host parameters' --output-separator ',' --form '' 0 0 0    \
	    'Host Name:'            1 1	"$HOST_NAME"        1 21 30 0           \
	    'Host Address:'         2 1	"$HOST_ADDRESS"  	2 21 30 0           \
	    'SSH User:'             3 1	"$HOST_USER"      	3 21 30 0           \
        'SSH Port:'             4 1	"$HOST_PORT" 	    4 21 30 0           \
        'Python Interpreter:'   5 1	"$HOST_PYTHON"	    5 21 30 0           \
        2>&1 1>&3)
    RET_CODE=$?
    exec 3>&-

    if [ "$RET_CODE" = 0 ]; then
        NEW_NAME="$(echo $DIALOG_RET | $CMD_AWK -F, '{print $1}')"
        NEW_ADDRESS="$(echo $DIALOG_RET | $CMD_AWK -F, '{print $2}')"
        NEW_USER="$(echo $DIALOG_RET | $CMD_AWK -F, '{print $3}')"
        NEW_PORT="$(echo $DIALOG_RET | $CMD_AWK -F, '{print $4}')"
        NEW_PYTHON="$(echo $DIALOG_RET | $CMD_AWK -F, '{print $5}')"

        if [ -z "$TESTING" ]; then
            if [ "$NEW_NAME" != "$HOST_NAME" ] || [ "$NEW_PYTHON" != "$HOST_PYTHON" ]; then
                HOST_LINE="$(grep "^$HOST_NAME\s*" "$FILE_HOST")"
                NEW_LINE="$HOST_LINE"
                if [ "$NEW_NAME" != "$HOST_NAME" ]; then
                    NEW_LINE="$(echo "$NEW_LINE" | $CMD_SED "s/$HOST_NAME/$NEW_NAME/")"
                    $CMD_SED -i "s/$HOST_NAME/$NEW_NAME/" "$FILE_FUNCTIONAL"
                    [ -f "$FILE_COMPANY" ] && $CMD_SED -i "s/$HOST_NAME/$NEW_NAME/" "$FILE_COMPANY"
                    $CMD_SED -i "s/$HOST_NAME/$NEW_NAME/" "$SSH_CONFIG"
                fi
                [ "$NEW_PYTHON" != "$HOST_PYTHON" ] && NEW_LINE="$(echo "$NEW_LINE" | $CMD_SED "s/ansible_python_interpreter=\/usr\/bin\/$HOST_PYTHON/ansible_python_interpreter=\/usr\/bin\/$NEW_PYTHON/")"
                $CMD_SED -i "s/$(echo "$HOST_LINE" | $CMD_SED 's/\//\\\//g')/$(echo "$NEW_LINE" | $CMD_SED 's/\//\\\//g')/" "$FILE_HOST"
            fi

            COUNT=0
            FOUND=''
            while read LINE; do
                COUNT="$(expr $COUNT + 1)"
                if echo $LINE | grep -q "^Host $NEW_NAME\s*$"; then
                    FOUND=1
                elif ! [ -z "$FOUND" ]; then
                    if echo $LINE | grep -q -P "^HostName $HOST_ADDRESS\s*$" && [ "$NEW_ADDRESS" != "$HOST_ADDRESS" ]; then
                        $CMD_SED -i "${COUNT}s/$HOST_ADDRESS/$NEW_ADDRESS/" "$SSH_CONFIG"
                    fi
                    if echo $LINE | grep -q -P "^User $HOST_USER\s*$" && [ "$NEW_USER" != "$HOST_USER" ]; then
                        $CMD_SED -i "${COUNT}s/$HOST_USER/$NEW_USER/" "$SSH_CONFIG"
                    fi
                    if echo $LINE | grep -q -P "^Port $HOST_PORT\s*$" && [ "$NEW_PORT" != "$HOST_PORT" ]; then
                        $CMD_SED -i "${COUNT}s/$HOST_PORT/$NEW_PORT/" "$SSH_CONFIG"
                    fi                   
                fi      
            done < "$SSH_CONFIG"
        else
            if [ "$NEW_NAME" != "$HOST_NAME" ]; then
                mv "$DIR_INVENTORY/$HOST_NAME" "$DIR_INVENTORY/$NEW_NAME"
                $CMD_SED -i "s/$HOST_NAME/$NEW_NAME/" "$DIR_INVENTORY/$NEW_NAME"
                $CMD_SED -i "s/$HOST_NAME/$NEW_NAME/" "$FILE_FUNCTIONAL"
                [ -f "$FILE_COMPANY" ] && $CMD_SED -i "s/$HOST_NAME/$NEW_NAME/" "$FILE_COMPANY"
            fi
            [ "$NEW_ADDRESS" != "$HOST_ADDRESS" ] && $CMD_SED -i "s/ansible_host=$HOST_ADDRESS/ansible_host=$NEW_ADDRESS/" "$DIR_INVENTORY/$NEW_NAME"
            [ "$NEW_USER" != "$HOST_USER" ] && $CMD_SED -i "s/ansible_user=$HOST_USER/ansible_user=$NEW_USER/" "$DIR_INVENTORY/$NEW_NAME"
            [ "$NEW_PORT" != "$HOST_PORT" ] && $CMD_SED -i "s/ansible_port=$HOST_PORT/ansible_port=$NEW_PORT/" "$DIR_INVENTORY/$NEW_NAME"
            [ "$NEW_PYTHON" != "$HOST_PYTHON" ] && $CMD_SED -i "s/ansible_python_interpreter=\/usr\/bin\/$HOST_PYTHON/ansible_python_interpreter=\/usr\/bin\/$NEW_PYTHON/" "$DIR_INVENTORY/$NEW_NAME"
        fi
    fi
}

# ping defined host/group
# parameters:
# $1 - inventory host name/group name
# return values:
# none
server_ping() {
    clear
    ansible -i "$DIR_INVENTORY" -m ping "$1"
    get_keypress
}

# get list of filtering tags
# parameters:
# none
# return values:
# list of tags
get_tags() {
    LIST_TAG="$(grep 'tags:' $FILE_PLAYBOOK | awk -F '[\\[\\]]' '{print $2}' | awk -F, '{for (i=1;i<=NF;i++) print $i}')"
    LIST_TAG+="$(grep -r '^\s*tags: ' $DIR_ROLES | awk -F 'tags: ' '{print $2}')"
    echo $LIST_TAG | xargs -n 1 | sort -u
}

# enter tag in dialog inputbox and run/test-run playbook for host/group
# parameters:
# $1 - inventory host name/group name
# return values:
# none
single_playbook() {
    ARRAY=()
    for TAG_NAME in $(get_tags); do
        if [ "$TAG_NAME" = 'base' ]; then
            ARRAY+=("$TAG_NAME" "$TAG_NAME" "on")
        else
            ARRAY+=("$TAG_NAME" "$TAG_NAME" "off")
        fi
    done

    exec 3>&1
    DIALOG_RET=$($DIALOG --clear --backtitle "$TITLE_MAIN $VERSION_MENU" --no-tags --checklist "Select filtering tags" 0 0 0 "${ARRAY[@]}" 2>&1 1>&3)
    RET_CODE=$?
    exec 3>&-
    if [ $RET_CODE = 0 ]; then
        clear
        if [ -z "$DIALOG_RET" ]; then
            if [ -z "$2" ]; then
                ansible-playbook "$FILE_PLAYBOOK" -l "$1"
            else
                ansible-playbook -C "$FILE_PLAYBOOK" -l "$1"
            fi
        else
            LIST_TAGS="$(echo $DIALOG_RET | sed 's/ /,/g')"
            if [ -z "$2" ]; then
                ansible-playbook "$FILE_PLAYBOOK" -l "$1" -t "$LIST_TAGS"
            else
                ansible-playbook -C "$FILE_PLAYBOOK" -l "$1" -t "$LIST_TAGS"
            fi
        fi
        get_keypress
        break
    fi
}

# test-run playbook for host/group
# parameters:
# $1 - inventory host name/group name
# return values:
# none
single_check() {
    group_playbook "$1" 'check'
}

# remove inventory host
# parameters:
# $1 - inventory host name
# return values:
# none
host_remove() {
    $DIALOG --backtitle 'Manage host' --yesno "Remove host '$1'?" 0 0
    if [ $? = 0 ]; then 
        rm -f "$DIR_INVENTORY/$1"
        $CMD_SED -i "/^Host $1\s*$/,/Host /d" "$SSH_CONFIG"
        $CMD_SED -i "/^$1\s*/d" "$FILE_HOST"
        $CMD_SED -i "/^$1\s*$/d" "$FILE_FUNCTIONAL"
        [ -f "$FILE_COMPANY" ] && $CMD_SED -i "/^$1\s*$/d" "$FILE_COMPANY"
    fi
}

# manage inventory host in dialog menu
# parameters:
# $1 - inventory host name
# return values:
# none
host_manage() {
    ITEMS_MANAGE=()
    ITEMS_MANAGE+=('host_functional' 'Manage functional groups')
    [ -f "$FILE_COMPANY" ] && ITEMS_MANAGE+=('host_company' 'Manage company groups')
    ITEMS_MANAGE+=('host_edit' 'Edit host parameters')
    ITEMS_MANAGE+=('server_ping' 'Ping')
    ITEMS_MANAGE+=('single_playbook' 'Run playbook for host')
    ITEMS_MANAGE+=('single_check' 'Test-run playbook for host')
    ITEMS_MANAGE+=('host_remove' 'Remove')

    exec 3>&1
    DIALOG_RET=$($DIALOG --clear --backtitle "$TITLE_MAIN $VERSION_MENU" --no-tags --cancel-label "Back" --ok-label "Ok" \
        --menu "Manage host '$1'" 0 40 0 "${ITEMS_MANAGE[@]}" 2>&1 1>&3)
    RET_CODE=$?
    exec 3>&-
    [ $RET_CODE = 0 ] && $DIALOG_RET "$1"
}

# add new inventory host to Ansible inventory (and SSH config for production hosts)
# parameters:
# $1 - inventory host name
# $2 - host type ('production' or 'testing')
# $3 - host address
# $4 - SSH user name
# $5 - SSH port
# $6 - Python intepreter
# $7 - list of associated functional groups
# $8 - list of associated company groups
# return values:
# none
host_add() {
    if [ "$2" = 'production' ]; then
        echo "Host $1"$'\n\t'"HostName $3"$'\n\t'"User $4"$'\n\t'"Port $5"$'\n' >> "$SSH_CONFIG"
        echo "$1 ansible_python_interpreter=/usr/bin/$6" >> "$FILE_HOST"
    else
        echo "$1 ansible_host=$3 ansible_user=$4 ansible_port=$5 ansible_python_interpreter=/usr/bin/$6" > "$DIR_INVENTORY/$1"
    fi

    for GROUP_NAME in $7; do
        add_host_functional "$1" "$GROUP_NAME"
    done

    if ! [ -z "$8" ]; then
        for GROUP_NAME in $8; do
            add_host_company "$1" "$GROUP_NAME"
        done
    fi
}

# get parameters for new inventory host from user and add it
# parameters:
# none
# return values:
# none
host_new() {
    while true; do
        exec 3>&1
        DIALOG_RET="$($DIALOG --clear --backtitle "$TITLE_MAIN $VERSION_MENU" --no-tags --inputbox "Enter inventory host name" 0 55 2>&1 1>&3)"
        RET_CODE=$?
        exec 3>&-
        [ "$RET_CODE" != 0 ] && return
        [ -z "$DIALOG_RET" ] || break
    done
    HOST_NAME="$DIALOG_RET"

    exec 3>&1
    DIALOG_RET="$($DIALOG --clear --backtitle "$TITLE_MAIN $VERSION_MENU" --no-tags \
        --menu "Select host type" 0 0 0                                             \
        "production" "production"                                                   \
        "testing" "testing"                                                         \
        2>&1 1>&3)"
    RET_CODE=$?
    exec 3>&-
    [ "$RET_CODE" != 0 ] && return
    HOST_TYPE="$DIALOG_RET"

    while true; do
        exec 3>&1
        DIALOG_RET="$($DIALOG --clear --backtitle "$TITLE_MAIN $VERSION_MENU" --no-tags --inputbox "Enter host address" 0 55 2>&1 1>&3)"
        RET_CODE=$?
        exec 3>&-
        [ "$RET_CODE" != 0 ] && return
        [ -z "$DIALOG_RET" ] || break
    done
    HOST_ADDRESS="$DIALOG_RET"

    while true; do
        exec 3>&1
        DIALOG_RET="$($DIALOG --clear --backtitle "$TITLE_MAIN $VERSION_MENU" --no-tags --inputbox "Enter SSH user" 0 55 'root' 2>&1 1>&3)"
        RET_CODE=$?
        exec 3>&-
        [ "$RET_CODE" != 0 ] && return
        [ -z "$DIALOG_RET" ] || break
    done
    HOST_USER="$DIALOG_RET"

    while true; do
        exec 3>&1
        DIALOG_RET="$($DIALOG --clear --backtitle "$TITLE_MAIN $VERSION_MENU" --no-tags --inputbox "Enter SSH port" 0 55 '22' 2>&1 1>&3)"
        RET_CODE=$?
        exec 3>&-
        [ "$RET_CODE" != 0 ] && return
        [ -z "$DIALOG_RET" ] || break
    done
    HOST_PORT="$DIALOG_RET"

    exec 3>&1
    DIALOG_RET="$($DIALOG --clear --backtitle "$TITLE_MAIN $VERSION_MENU" --no-tags \
        --menu "Select Python interpreter" 0 0 0                                    \
        "python" "Python 2.x"                                                       \
        "python3" "Python 3.x"                                                      \
        2>&1 1>&3)"
    RET_CODE=$?
    exec 3>&-
    [ "$RET_CODE" != 0 ] && return
    HOST_PYTHON="$DIALOG_RET"

    ARRAY=()
    for GROUP_NAME in $(get_functional); do
        ARRAY+=("$GROUP_NAME" "$GROUP_NAME" "off")
    done

    exec 3>&1
    DIALOG_RET=$($DIALOG --clear --backtitle "$TITLE_MAIN $VERSION_MENU" --no-tags --checklist "Select associated functional groups" 0 0 0 "${ARRAY[@]}" 2>&1 1>&3)
    RET_CODE=$?
    exec 3>&-
    [ "$RET_CODE" != 0 ] && return
    LIST_FUNCTIONAL="$DIALOG_RET"

    if [ -f "$FILE_COMPANY" ]; then
        ARRAY=()
        for GROUP_NAME in $(get_company); do
            ARRAY+=("$GROUP_NAME" "$GROUP_NAME" "off")
        done

        exec 3>&1
        DIALOG_RET=$($DIALOG --clear --backtitle "$TITLE_MAIN $VERSION_MENU" --no-tags --checklist "Select associated company groups" 0 0 0 "${ARRAY[@]}" 2>&1 1>&3)
        RET_CODE=$?
        exec 3>&-
        [ "$RET_CODE" != 0 ] && return
        LIST_COMPANY="$DIALOG_RET"
    fi

    host_add "$HOST_NAME" "$HOST_TYPE" "$HOST_ADDRESS" "$HOST_USER" "$HOST_PORT" "$HOST_PYTHON" "$LIST_FUNCTIONAL" "$LIST_COMPANY"
}

# show list of inventory hosts in dialog menu with option to manage hosts
# parameters:
# none
# return values:
# none
host_menu() {
    while true; do
        LIST_HOST="$(get_hosts)"
        if ! [ -z "$LIST_HOST" ]; then
            ITEMS_HOST=()
            for HOST_NAME in $LIST_HOST; do
                ITEMS_HOST+=("$HOST_NAME" "$HOST_NAME")
            done

            exec 3>&1
            DIALOG_RET=$($DIALOG --clear --title 'Manage hosts' --backtitle "$TITLE_MAIN $VERSION_MENU" --ok-label 'Manage' --cancel-label 'Back' --extra-button --extra-label 'New' --no-tags --menu '' 20 40 40 "${ITEMS_HOST[@]}" 2>&1 1>&3)
            RET_CODE=$?
            exec 3>&-
            if [ $RET_CODE = 0 ]; then
                host_manage "$DIALOG_RET"
            elif [ $RET_CODE = 3 ]; then
                host_new
            else
                break
            fi
        else
            $DIALOG --clear --title 'Manage hosts' --backtitle "$TITLE_MAIN $VERSION_MENU" --ok-label 'New' --cancel-label 'Back' --no-tags --menu '' 20 40 40 '' 'No hosts'
            if [ $RET_CODE = 0 ]; then
                host_new
            else
                break
            fi
        fi
    done
}

# select inventory host in dialog menu to add to group
# parameters:
# $1 - group name
# $2 - list of inventory hosts
# $3 - group type
# return values:
# none
group_add_host() {
    ARRAY=()
    for HOST_NAME in $2; do
        ARRAY+=("$HOST_NAME" "$HOST_NAME")
    done

    exec 3>&1
    DIALOG_RET=$($DIALOG --clear --backtitle "Manage associated hosts" --ok-label 'Add' --cancel-label 'Cancel' --no-tags --menu 'Add host' 20 40 40 "${ARRAY[@]}" 2>&1 1>&3)
    RET_CODE=$?
    exec 3>&-
    [ $RET_CODE = 0 ] && add_host_$3 "$DIALOG_RET" "$1"
}

# show list of inventory hosts associated with group in dialog menu with option to add/remove associated hosts
# parameters:
# $1 - group name
# $2 - group type
# return values:
# none
group_hosts() {
    while true; do
        LIST_INCLUDED="$(get_$2_hosts $1 | $CMD_SED 's/,/ /g')"
        if ! [ -z "$LIST_INCLUDED" ]; then
            LIST_MISSING=''
            for HOST_NAME in $(get_hosts); do                   
                echo "$LIST_INCLUDED" | grep -q "$HOST_NAME" || LIST_MISSING+=" $HOST_NAME"
            done

            ARRAY=()
            for HOST_NAME in $LIST_INCLUDED; do
                ARRAY+=("$HOST_NAME" "$HOST_NAME")
            done

            exec 3>&1
            DIALOG_RET=$($DIALOG --clear --backtitle "Manage group" --ok-label 'Remove' --extra-button --extra-label 'Add' --cancel-label 'Back' --no-tags --menu 'Associated hosts' 0 0 0 "${ARRAY[@]}" 2>&1 1>&3)
            RET_CODE=$?
            exec 3>&-
            if [ $RET_CODE = 0 ]; then
                remove_host_$2 "$DIALOG_RET" "$1"
            elif [ $RET_CODE = 3 ]; then
                group_add_host "$1" "$LIST_MISSING" "$2"
            else
                break
            fi
        else
            $DIALOG --clear --backtitle "Manage group" --ok-label 'Add' --cancel-label 'Back' --no-tags --menu 'Associated hosts' 0 0 0 '' 'No hosts'
            RET_CODE=$?
            if [ $RET_CODE = 0 ]; then
                group_add_host "$1" "$(get_hosts)" "$2"
            else
                break
            fi
        fi
    done
}

# show list of inventory hosts associated with functional group in dialog menu with option to add/remove associated hosts
# parameters:
# $1 - group name
# return values:
# none
functional_hosts() {
    group_hosts "$1" 'functional'
}

# show list of inventory hosts associated with company group in dialog menu with option to add/remove associated hosts
# parameters:
# $1 - group name
# return values:
# none
company_hosts() {
    group_hosts "$1" 'company'
}

# remove group
# parameters:
# $1 - group name
# $2 - group file
# return values:
# none
group_remove() {
    $DIALOG --backtitle 'Manage group' --yesno "Remove group '$1'?" 0 0
    [ $? = 0 ] && $CMD_SED -i "/^\[$1]\s*$/,/^\[/d" "$2"
}

# remove functional group
# parameters:
# $1 - group name
# return values:
# none
functional_remove() {
    group_remove "$1" "$FILE_FUNCTIONAL"
}

# remove company group
# parameters:
# $1 - group name
# return values:
# none
company_remove() {
    group_remove "$1" "$FILE_COMPANY"
}

# manage group in dialog menu
# parameters:
# $1 - group name
# $2 - group type
# return values:
# none
group_manage() {
    exec 3>&1
    DIALOG_RET=$($DIALOG --clear --backtitle "$TITLE_MAIN $VERSION_MENU" --no-tags \
        --cancel-label "Back" --ok-label "Ok" --menu "Manage group '$1'" 0 40 0    \
        "$2_hosts" "Manage hosts"                                                  \
        "server_ping" "Ping"                                                       \
        "single_playbook" "Run playbook for group"                                 \
        "single_check" "Test-run playbook for group"                                \
        "$2_remove" "Remove"                                                       \
        2>&1 1>&3)
    RET_CODE=$?
    exec 3>&-
    [ $RET_CODE = 0 ] && $DIALOG_RET "$1"
}

# add new group to Ansible inventory
# parameters:
# $1 - group name
# $2 - list of associated inventory hosts
# $3 - group file
# return values:
# none
group_add() {
    echo "[$1]" >> "$3"

    for HOST_NAME in $2; do
        add_host_group "$HOST_NAME" "$1" "$3"
    done
}

# add new functional group to Ansible inventory
# parameters:
# $1 - group name
# $2 - list of associated inventory hosts
# return values:
# none
functional_add() {
    group_add "$1" "$2" "$FILE_FUNCTIONAL"
}

# add new company group to Ansible inventory
# parameters:
# $1 - group name
# $2 - list of associated inventory hosts
# return values:
# none
company_add() {
    group_add "$1" "$2" "$FILE_COMPANY"
}

# get parameters for new group from user and add it
# parameters:
# $1 - group type
# return values:
# none
group_new() {
    while true; do
        exec 3>&1
        DIALOG_RET="$($DIALOG --clear --backtitle "$TITLE_MAIN $VERSION_MENU" --no-tags --inputbox "Enter inventory group name" 0 55 2>&1 1>&3)"
        RET_CODE=$?
        exec 3>&-
        [ "$RET_CODE" != 0 ] && return
        [ -z "$DIALOG_RET" ] || break
    done
    GROUP_NAME="$DIALOG_RET"

    ARRAY=()
    for HOST_NAME in $(get_hosts); do
        ARRAY+=("$HOST_NAME" "$HOST_NAME" "off")
    done

    exec 3>&1
    DIALOG_RET=$($DIALOG --clear --backtitle "$TITLE_MAIN $VERSION_MENU" --no-tags --checklist "Select associated hosts" 0 0 0 "${ARRAY[@]}" 2>&1 1>&3)
    RET_CODE=$?
    exec 3>&-
    if [ $RET_CODE = 0 ]; then
        $1_add "$GROUP_NAME" "$DIALOG_RET"
    else
        return
    fi
}

# show list of groups in dialog menu with option to manage groups
# parameters:
# $1 - group type
# return values:
# none
group_menu() {
    while true; do
        LIST_GROUP="$(get_$1)"
        if ! [ -z "$LIST_GROUP" ]; then
            ITEMS_GROUP=()
            for GROUP_NAME in $LIST_GROUP; do
                ITEMS_GROUP+=("$GROUP_NAME" "$GROUP_NAME")
            done

            exec 3>&1
            DIALOG_RET=$($DIALOG --clear --title 'Manage groups' --backtitle "$TITLE_MAIN $VERSION_MENU" --ok-label 'Manage' --cancel-label 'Back' --extra-button --extra-label 'New' --no-tags --menu '' 0 40 0 "${ITEMS_GROUP[@]}" 2>&1 1>&3)
            RET_CODE=$?
            exec 3>&-
            if [ $RET_CODE = 0 ]; then
                group_manage "$DIALOG_RET" "$1"
            elif [ $RET_CODE = 3 ]; then
                group_new "$1"
            else
                break
            fi
        else
            $DIALOG --clear --title 'Manage groups' --backtitle "$TITLE_MAIN $VERSION_MENU" --ok-label 'New' --cancel-label 'Back' --no-tags --menu '' 0 40 0 '' 'No groups'
            if [ $RET_CODE = 0 ]; then
                group_new "$1"
            else
                break
            fi
        fi
    done  
}

# show list of functional groups in dialog menu with option to manage groups
# parameters:
# none
# return values:
# none
functional_menu() {
    group_menu 'functional'
}

# show list of company groups in dialog menu with option to manage groups
# parameters:
# none
# return values:
# none
company_menu() {
    group_menu 'company'
}

# define filter and run Ansible playbook for filtered list of hosts
# parameters:
# $1 - if empty run playbook, else test-run only
# return values:
# none
playbook_run() {
	FILTER_PLAYBOOK="$(grep '^\s*-\?\s*hosts: ' "$FILE_PLAYBOOK" | head -1 | $CMD_AWK -F 'hosts:' '{print $2}' | $CMD_SED 's/"//g' | $CMD_SED 's/,/ /g')"
    LIST_HOST=''
	for FILTER_HOST in $FILTER_PLAYBOOK; do
		if echo "$FILTER_HOST" | grep -q -v '^!'; then
			if [ "$FILTER_HOST" = 'all' ]; then
                LIST_HOST+="$(get_hosts) "
            elif [ "$FILTER_HOST" = 'localhost' ]; then
                LIST_HOST+='localhost '
            else
                LIST_HOST+="$(get_hosts | grep "$(echo $FILTER_HOST | $CMD_SED 's/*//g')") "
            fi
		fi
	done
	for FILTER_HOST in $FILTER_PLAYBOOK; do
		echo "$FILTER_HOST" | grep -q '^!' && LIST_HOST="$(echo $LIST_HOST | xargs -n 1 | grep -v "$(echo $FILTER_HOST | $CMD_SED 's/[!*]//g')" | xargs) "
	done
	if ! [ -z "$LIST_HOST" ]; then	
		FILTER_HOST=''
		while true; do
            LIST_FILTERED="$(for NAME_HOST in $LIST_HOST; do if echo "$FILTER_HOST" | grep -q '^!'; then echo "$NAME_HOST" | grep -v "$(echo $FILTER_HOST | $CMD_AWK -F '!' '{print $2}')"; else echo "$NAME_HOST" | grep "$FILTER_HOST"; fi; done)"
			LIST_SHOWN='Selected hosts:'$'\n'
			for NAME_HOST in $LIST_FILTERED; do LIST_SHOWN+=$'\n'"$NAME_HOST"; done
			$DIALOG --clear --title 'Run playbook' --backtitle 'Manage playbook' --ok-label 'Ok' --cancel-label 'Cancel' --extra-button --extra-label 'Filter' --yesno "$LIST_SHOWN" 20 40
			RET_CODE=$?
			if [ $RET_CODE = 0 ]; then
                ARRAY=()
                for TAG_NAME in $(get_tags); do
                    if [ "$TAG_NAME" = 'base' ]; then
                        ARRAY+=("$TAG_NAME" "$TAG_NAME" "on")
                    else
                        ARRAY+=("$TAG_NAME" "$TAG_NAME" "off")
                    fi
                done

                exec 3>&1
                DIALOG_RET=$($DIALOG --clear --backtitle "$TITLE_MAIN $VERSION_MENU" --no-tags --checklist "Select filtering tags" 0 0 0 "${ARRAY[@]}" 2>&1 1>&3)
                RET_CODE=$?
                exec 3>&-
                if [ $RET_CODE = 0 ]; then
				    clear
                    if [ -z "$DIALOG_RET" ]; then
				        if [ -z "$1" ]; then
				        	ansible-playbook "$FILE_PLAYBOOK" -l "$FILTER_HOST"
				        else
				        	ansible-playbook -C "$FILE_PLAYBOOK" -l "$FILTER_HOST"
				        fi
                    else
                        if [ -z "$1" ]; then
				        	ansible-playbook "$FILE_PLAYBOOK" -l "$FILTER_HOST" -t "$DIALOG_RET"
				        else
				        	ansible-playbook -C "$FILE_PLAYBOOK" -l "$FILTER_HOST" -t "$DIALOG_RET"
				        fi
                    fi
				    get_keypress
				    break
                fi
			elif [ $RET_CODE = 3 ]; then
                exec 3>&1
                DIALOG_RET=$($DIALOG --clear --title 'Run playbook' --backtitle 'Manage playbook' --ok-label 'Apply' --cancel-label 'Cancel' --inputbox 'Enter host filter' 0 0 "$FILTER_HOST" 2>&1 1>&3)
                RET_CODE=$?
                exec 3>&-
                [ $RET_CODE = 0 ] && FILTER_HOST="$DIALOG_RET"
			else
				break
			fi
		done
	fi
}

# define filter and test-run Ansible playbook for filtered list of hosts
# parameters:
# none
# return values:
# none
playbook_check() {
	playbook_run 'check'
}

# check syntax of Ansible playbook
# parameters:
# none
# return values:
# none
playbook_syntax() {
	clear
	ansible-playbook --syntax-check "$FILE_PLAYBOOK"
	get_keypress
}

# edit Ansible playbook
# parameters:
# none
# return values:
# none
playbook_edit() {
	$EDITOR "$FILE_PLAYBOOK"
}

# manage Ansible playbook in dialog menu
# parameters:
# none
# return values:
# none
playbook_manage() {
    ARRAY=()
    ARRAY+=('playbook_run' 'Run')
	ARRAY+=('playbook_check' 'Test-run')
	ARRAY+=('playbook_syntax' 'Check syntax')
	ARRAY+=('playbook_edit' 'Edit')
    exec 3>&1
    DIALOG_RET=$($DIALOG --clear --title 'Manage Ansible playbook' --backtitle 'Ansible playbooks' --no-tags        \
        --ok-label 'Select' --cancel-label 'Back' --menu '' 0 0 0 "${ARRAY[@]}" 2>&1 1>&3)
    RET_CODE=$?
    exec 3>&-
    [ $RET_CODE = 0 ] && $DIALOG_RET
}

# edit role sections
# parameters:
# $1 - role section (tasks/handlers/vars/templates/files)
# $2 - role name
# return values:
# none
role_edit() {
    $EDITOR "$DIR_ROLES/$2/$1"
}

# manage role in dialog menu
# parameters:
# $1 - role name
# return values:
# none
role_manage() {
    ARRAY=()
    ARRAY+=('tasks' 'tasks')
	ARRAY+=('handlers' 'handlers')
    ARRAY+=('vars' 'vars')
    ARRAY+=('templates' 'templates')
    ARRAY+=('files' 'files')
    exec 3>&1
    DIALOG_RET=$($DIALOG --clear --title 'Manage role' --backtitle 'Ansible roles' --no-tags --ok-label 'Select' --cancel-label 'Back' --menu '' 0 0 0 "${ARRAY[@]}" 2>&1 1>&3)
    RET_CODE=$?
    exec 3>&-
    [ $RET_CODE = 0 ] && role_edit "$DIALOG_RET" "$1"
}

# get parameters for new role from user and add it
# parameters:
# none
# return values:
# none
role_new() {
    while true; do
        exec 3>&1
        DIALOG_RET="$($DIALOG --clear --backtitle "$TITLE_MAIN $VERSION_MENU" --no-tags --inputbox "Enter role name" 0 55 2>&1 1>&3)"
        RET_CODE=$?
        exec 3>&-
        [ "$RET_CODE" != 0 ] && return
        [ -z "$DIALOG_RET" ] || break
    done

    ansible-galaxy init "$DIALOG_RET" --init-path "$DIR_ROLES" &>/dev/null
}

# show list of roles in dialog menu with option to manage role
# parameters:
# none
# return values:
# none
role_menu() {
    while true; do
        LIST_ROLE="$(ls $DIR_ANSIBLE/roles)"
        if ! [ -z "$LIST_ROLE" ]; then
            ITEMS_ROLE=()
            for ROLE_NAME in $LIST_ROLE; do
                ITEMS_ROLE+=("$ROLE_NAME" "$ROLE_NAME")
            done

            exec 3>&1
            DIALOG_RET=$($DIALOG --clear --title 'Manage roles' --backtitle "$TITLE_MAIN $VERSION_MENU" --ok-label 'Manage' --cancel-label 'Back' --extra-button --extra-label 'New' --no-tags --menu '' 0 40 0 "${ITEMS_ROLE[@]}" 2>&1 1>&3)
            RET_CODE=$?
            exec 3>&-
            if [ $RET_CODE = 0 ]; then
                role_manage "$DIALOG_RET"
            elif [ $RET_CODE = 3 ]; then
                role_new
            else
                break
            fi
        else
            $DIALOG --clear --title 'Manage roles' --backtitle "$TITLE_MAIN $VERSION_MENU" --ok-label 'New' --cancel-label 'Back' --no-tags --menu '' 0 40 0 '' 'No roles'
            if [ $RET_CODE = 0 ]; then
                role_new
            else
                break
            fi
        fi
    done 
}

# edit Ansible config
# parameters:
# none
# return values:
# none
edit_config() {
    $EDITOR "$FILE_CONFIG"
}

# main menu
ITEMS_MAIN=()
ITEMS_MAIN+=('host_menu' 'Hosts')
ITEMS_MAIN+=('functional_menu' 'Functional groups')
[ -f "$FILE_COMPANY" ] && ITEMS_MAIN+=('company_menu' 'Company groups')
ITEMS_MAIN+=('role_menu' 'Roles')
ITEMS_MAIN+=('playbook_manage' "site.yml")
ITEMS_MAIN+=('edit_config' 'ansible.cfg')
while true; do
    exec 3>&1
    DIALOG_RET=$($DIALOG --clear --title "$TITLE_MAIN $VERSION_MENU" --cancel-label 'Exit' --no-tags --menu '' 0 0 0 "${ITEMS_MAIN[@]}" 2>&1 1>&3)
    RET_CODE=$?
    exec 3>&-
    if [ $RET_CODE = 0 ]; then
        $DIALOG_RET
    else
        break
    fi
done
clear
