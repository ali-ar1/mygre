#!/bin/bash
CYAN=$(tput setaf 6)
YELLOW=$(tput setaf 3)
GREEN=$(tput setaf 2)
RED=$(tput setaf 1)
RESET=$(tput sgr0)

STATE_DIR="/etc/vatan-gre"
STATE_FILE="$STATE_DIR/tunnels.conf"   # format: name|role|local_ip|remote_ip|tun_local_ip|tun_peer_ip|mtu
mkdir -p "$STATE_DIR"
touch "$STATE_FILE"

banner() {
    echo -e "${CYAN}"
    echo "===================================="
    echo "        GitHub: vatanhost"
    echo "   GRE Tunnel Multi-Setup Script"
    echo "===================================="
    echo -e "${RESET}"
}

# find the next free index for tunnel naming and subnet allocation
next_index() {
    local max=0
    while IFS='|' read -r name role local_ip remote_ip tun_local tun_peer mtu; do
        [[ -z "$name" ]] && continue
        idx=$(echo "$name" | grep -oE '[0-9]+$')
        if [[ -n "$idx" && "$idx" -gt "$max" ]]; then
            max=$idx
        fi
    done < "$STATE_FILE"
    echo $((max + 1))
}

list_tunnels() {
    if [[ ! -s "$STATE_FILE" ]]; then
        echo -e "${YELLOW}No tunnels have been created yet.${RESET}"
        return 1
    fi
    echo -e "${CYAN}Active tunnels:${RESET}"
    local i=1
    while IFS='|' read -r name role local_ip remote_ip tun_local tun_peer mtu; do
        [[ -z "$name" ]] && continue
        echo "$i) $name  |  role: $role  |  local: $local_ip -> remote: $remote_ip  |  internal IP: $tun_local (peer: $tun_peer)  |  MTU: $mtu"
        i=$((i+1))
    done < "$STATE_FILE"
    return 0
}

add_tunnel() {
    echo "Select this server's role:"
    echo "1 - IRAN"
    echo "2 - FOREIGN"
    read -p "Enter 1 or 2: " LOCATION

    if [[ "$LOCATION" != "1" && "$LOCATION" != "2" ]]; then
        echo -e "${RED}[!] Invalid selection.${RESET}"
        return 1
    fi

    read -p "Enter IRAN server IP: " IP_IRAN
    read -p "Enter FOREIGN server IP: " IP_FOREIGN

    IDX=$(next_index)
    TUN_NAME="vatan-m${IDX}"

    echo "Should the internal tunnel IP (/30 subnet) be assigned automatically or manually?"
    echo "1 - Automatic (recommended)"
    echo "2 - Manual (use this if the other side already uses a specific subnet)"
    read -p "Enter 1 or 2: " SUBNET_MODE

    if [[ "$SUBNET_MODE" == "2" ]]; then
        read -p "Internal IP for this server (e.g. 192.168.30.2): " TUN_LOCAL_IP
        read -p "Internal IP for the peer side (e.g. 192.168.30.1): " TUN_PEER_IP
    else
        BLOCK=$(( (IDX - 1) * 4 ))
        IP_A="192.168.30.$(( BLOCK + 1 ))"
        IP_B="192.168.30.$(( BLOCK + 2 ))"
        if [[ "$LOCATION" == "1" ]]; then
            TUN_LOCAL_IP="$IP_B"
            TUN_PEER_IP="$IP_A"
        else
            TUN_LOCAL_IP="$IP_A"
            TUN_PEER_IP="$IP_B"
        fi
        echo -e "${YELLOW}[i] Internal IP for this server: $TUN_LOCAL_IP  |  Internal IP for the peer: $TUN_PEER_IP${RESET}"
        echo -e "${YELLOW}[i] On the peer server, make sure to enter this same pair (swapped) so they match.${RESET}"
    fi

    read -p "Enter tunnel MTU [default 1436]: " TUN_MTU
    TUN_MTU=${TUN_MTU:-1436}

    if [[ "$LOCATION" == "1" ]]; then
        echo "[*] Setting up tunnel for IRAN server -> $IP_FOREIGN ..."
        sudo ip tunnel add "$TUN_NAME" mode gre local "$IP_IRAN" remote "$IP_FOREIGN" ttl 255
        sudo ip link set dev "$TUN_NAME" up
        sudo ip addr add "${TUN_LOCAL_IP}/30" dev "$TUN_NAME"
        sudo ip link set dev "$TUN_NAME" mtu "$TUN_MTU"

        sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null

        read -p "Add NAT forwarding for this tunnel (to $TUN_PEER_IP)? (y/n): " DO_NAT
        if [[ "$DO_NAT" == "y" || "$DO_NAT" == "Y" ]]; then
            sudo iptables -t nat -A PREROUTING -p tcp --dport 22 -j DNAT --to-destination "$TUN_LOCAL_IP"
            sudo iptables -t nat -A PREROUTING -j DNAT --to-destination "$TUN_PEER_IP"
            sudo iptables -t nat -A POSTROUTING -j MASQUERADE
        fi

        ROLE="IRAN"
    else
        echo "[*] Setting up tunnel for FOREIGN server -> $IP_IRAN ..."
        sudo ip tunnel add "$TUN_NAME" mode gre local "$IP_FOREIGN" remote "$IP_IRAN" ttl 255
        sudo ip link set dev "$TUN_NAME" up
        sudo ip addr add "${TUN_LOCAL_IP}/30" dev "$TUN_NAME"
        sudo ip link set dev "$TUN_NAME" mtu "$TUN_MTU"

        read -p "Enable blocking of incoming ICMP on this server? (y/n): " DO_ICMP
        if [[ "$DO_ICMP" == "y" || "$DO_ICMP" == "Y" ]]; then
            sudo iptables -A INPUT --proto icmp -j DROP
        fi

        ROLE="FOREIGN"
    fi

    echo "${TUN_NAME}|${ROLE}|${IP_IRAN}|${IP_FOREIGN}|${TUN_LOCAL_IP}|${TUN_PEER_IP}|${TUN_MTU}" >> "$STATE_FILE"
    echo -e "${GREEN}[+] Tunnel $TUN_NAME created successfully.${RESET}"

    read -p "Add another tunnel right now? (y/n): " AGAIN
    if [[ "$AGAIN" == "y" || "$AGAIN" == "Y" ]]; then
        add_tunnel
    fi
}

delete_single_tunnel() {
    list_tunnels || return 0
    read -p "Enter the number of the tunnel to delete (0 to cancel): " NUM
    [[ "$NUM" == "0" ]] && return 0

    local i=1
    local target_line=""
    while IFS='|' read -r name role local_ip remote_ip tun_local tun_peer mtu; do
        [[ -z "$name" ]] && continue
        if [[ "$i" == "$NUM" ]]; then
            target_line="$name|$role|$local_ip|$remote_ip|$tun_local|$tun_peer|$mtu"
        fi
        i=$((i+1))
    done < "$STATE_FILE"

    if [[ -z "$target_line" ]]; then
        echo -e "${RED}[!] Invalid number.${RESET}"
        return 1
    fi

    local del_name=$(echo "$target_line" | cut -d'|' -f1)
    echo "[*] Deleting tunnel $del_name ..."
    sudo ip link set dev "$del_name" down 2>/dev/null
    sudo ip tunnel del "$del_name" 2>/dev/null
    sudo ip link delete "$del_name" 2>/dev/null

    grep -vF "$target_line" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    echo -e "${GREEN}[+] Tunnel $del_name deleted.${RESET}"
    echo -e "${YELLOW}[i] Note: this does not remove any iptables rules (NAT/ICMP) that were added manually; use 'Delete all tunnels' for a full cleanup.${RESET}"
}

delete_all_tunnels() {
    if [[ ! -s "$STATE_FILE" ]]; then
        echo -e "${YELLOW}No tunnels to delete.${RESET}"
        return 0
    fi
    read -p "Are you sure you want to delete all tunnels? (y/n): " CONFIRM
    [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && return 0

    while IFS='|' read -r name role local_ip remote_ip tun_local tun_peer mtu; do
        [[ -z "$name" ]] && continue
        echo "[*] Deleting $name ..."
        sudo ip link set dev "$name" down 2>/dev/null
        sudo ip tunnel del "$name" 2>/dev/null
        sudo ip link delete "$name" 2>/dev/null
    done < "$STATE_FILE"

    > "$STATE_FILE"

    read -p "Also clear the NAT/ICMP iptables rules added by this script? (y/n): " CLEAN_IPT
    if [[ "$CLEAN_IPT" == "y" || "$CLEAN_IPT" == "Y" ]]; then
        sudo iptables -t nat -F PREROUTING
        sudo iptables -t nat -F POSTROUTING
        sudo iptables -F INPUT
        echo -e "${YELLOW}[i] Note: this clears ALL rules in PREROUTING/POSTROUTING/INPUT, not just this script's.${RESET}"
    fi

    echo -e "${GREEN}[+] All tunnels deleted.${RESET}"
}

main_menu() {
    banner
    while true; do
        echo ""
        echo "1 - Add a new tunnel"
        echo "2 - List tunnels"
        echo "3 - Delete a specific tunnel"
        echo "4 - Delete all tunnels"
        echo "0 - Exit"
        read -p "Choose: " CHOICE
        case "$CHOICE" in
            1) add_tunnel ;;
            2) list_tunnels ;;
            3) delete_single_tunnel ;;
            4) delete_all_tunnels ;;
            0) exit 0 ;;
            *) echo -e "${RED}[!] Invalid selection.${RESET}" ;;
        esac
    done
}

main_menu
