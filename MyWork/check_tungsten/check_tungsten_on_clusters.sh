#!/usr/bin/env bash
# check_tungsten_on_clusters.sh: Tool to help stop/start tungsten during the
# SLV migration to AWS.

# Author = 'Ruben Ricaurte <ricaurtef@gmail.com>'


# Global definitions.
readonly hosts="$HOME/hosts"


clean_up() {
    local temp_file="$1"

    trap 'rm -f -- "$temp_file"' RETURN
}


add_host_fingerprint() {
    local known_hosts_dir="$HOME/.ssh"

    [[ ! -d "$known_hosts_dir" ]] && mkdir -p "$known_hosts_dir"

    # Add fingerprint if there's no entry for the host in known_hosts.
    while read -r host; do
        if ! (ssh-keygen -F "$host" > /dev/null); then
            echo "Adding: '$host' to the known_hosts file."
            if ! (ssh-keyscan -H "$host" >> "$known_hosts_dir/known_hosts")
            then
                echo -e "Failed to add: '$host' to known_hosts.\nAborted." >&2
                exit 1
            fi
        fi
    done < "$hosts"
}


get_tungsten_hosts() {
    local temp_file
    local passwd="$1"
    local headnode="${2}"
    local user="${4:-$USER}"

    export SSHPASS="$passwd"
    temp_file=$(mktemp -t _tungsten.XXXXXXX) || return 1

    # Command that will run on the headnode to find all tungstens.
	read -rd '' cmd <<- EOF
        for cluster in  \$(zuodb clusters show | grep '^s'); do
            zuodb cluster \$cluster topology -rs | awk -F '[ :]' '/+T/{print \$2}';
        done
	EOF

    # Connect to the headnode and make the magic begin.
    sshpass -e ssh -q "$user@$headnode" "$cmd" | tee "$temp_file"

    # Dump the temporary inventory to the hosts file.
    if (sort -u < "$temp_file" > "$hosts"); then
        echo "$hosts file created successfully. Have fun!"
    fi

    # Tidying up the house.
    clean_up "$temp_file"
}


tungsten_operations() {
    local temp_file forks
    local operation="$1"
    local passwd="$2"
    local tungsten_dir='opt/tungsten_3'
    local tungsten_bin='tungsten/tungsten-replicator/bin/replicator'
    local status_report="$HOME/tungsten_status_report.txt"
    local playbook='tungsten_actions.yml'

    if [[ ! -f "$hosts" || ! -s "$hosts" ]]; then
        echo 'Inventory file is missing or empty.' >&2
        return 1
    fi

    # Number of forks.
    forks=$(wc -l < "$hosts")

    # Add hosts fingerprint before the show starts.
    add_host_fingerprint

    # Command that will run to carry out the selected operation.
    read -rd '' cmd <<- EOF
        shards=\$(ls /$tungsten_dir | grep -E "^[0-9]*[0-9][a-z]?$");
        for shard in \$shards; do
            /$tungsten_dir/\$shard/$tungsten_bin $operation;
        done
	EOF

    # Let's the magic begin!
    [[ "$operation" == 'status' ]] && temp_file=$(mktemp -t _tun_status.XXXXXX)

    ansible-playbook "$playbook" --inventory "$hosts" --ask-pass --become \
        --forks "$forks" \
        --extra-vars "tungsten_dir=$tungsten_dir tungsten_bin=$tungsten_bin \
                      operation=$operation temp_file=$temp_file"

    if [[ "$operation" == 'status' ]]; then
        read -rd '' awk_cmd <<- EOF
            BEGIN {
                print "HOST\t\t\tSHARD\tPID\tSTATUS"
                print "---"
            }

            /^[0-9A-Za-z]/{
               \$4 == "STARTED" ? ++started: ++stopped
                printf "%s\\t%s\\t%s\\t%s\\n", \$1, \$2, \$3, \$4 | "sort -k2n"
            }

            END {
                print "---"
                printf "Total Started:\\t%s\\n", started
                printf "Total Stopped:\\t%s\\n", stopped
                printf "Total Tungsten:\\t%s\\n", started + stopped
                print "---"
            }
		EOF

        if [[ -s "$temp_file" ]]; then
            awk "$awk_cmd" "$temp_file" | tee "$status_report" | less
        else
            echo "Something went wrong, '$temp_file' is empty." >&2
        fi

        # Tidying up the house.
        clean_up "$temp_file"
    fi
}


display_menu() {
    clear

	cat <<- EOF
1. Get the inventory file.
2. Stop tungsten.
3. Start tungsten.
4. Get tungsten status.
0. Quit.
	EOF

    read -rp 'Enter selection [0-4] > '
}


main() {
    local delay='read -n 1 -rsp "Press any key to continue..."'

    while true; do
        display_menu

        case "$REPLY" in
            0)
                echo 'Program terminated'
                break
                ;;
            [1-4])
                clear
                ;;&
            1)  # Get the list of hosts where tungsten is running.
                read -rsp 'SSH password: ' passwd
                time get_tungsten_hosts "$passwd"
                eval "$delay"
                ;;&
            2)
                operation='stop'
                ;;&
            3)
                operation='start'
                ;;&
            4)
                operation='status'
                ;;&
            [2-4])  # Tungsten actions for every host in the inventory.
                tungsten_operations "$operation"
                eval "$delay"
                ;;
            *)
                echo 'Invalid entry.' >&2
                sleep "3"
                ;;
        esac
    done
}


main "$@"
