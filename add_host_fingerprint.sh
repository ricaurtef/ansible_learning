#! /usr/bin/env bash
# script_name: Description of the script purpose.

# Author: Ruben Ricaurte <ricaurtef@gmail.com>


usage() {
    echo "Usage: $(basename "${0%.*}") INVENTORY"

    return
}


add_host_fingerprint() {
    local known_hosts_dir inventory
    known_hosts_dir="$HOME/.ssh"
    inventory="$1"

    [[ ! -d "$known_hosts_dir" ]] && mkdir -p "$known_hosts_dir"

    # Add fingerprint if there's no entry for the host in known_hosts.
    while read -r host; do
        if ! (ssh-keygen -F "$host" > /dev/null); then
            echo "Adding: '$host' to the known_hosts file."
            if ! (ssh-keyscan -H "$host" >> "$known_hosts_dir/known_hosts")
            then
                echo -e "Failed to add: '$host' to known_hosts.\nAborted." >&2
                return 1
            fi
        fi
    done < <(grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' "$inventory")
}


main() {
    local inventory
    inventory="$1"

    # Validate input arguments.
    [[ $# -gt 1 || ! -f "$inventory" ]] && { usage >&2; return 1; }

    add_host_fingerprint "$inventory"
}


main "$@"
