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

# پیدا کردن ایندکس بعدی برای نام‌گذاری تانل و ساب‌نت
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
        echo -e "${YELLOW}هیچ تانلی هنوز ساخته نشده.${RESET}"
        return 1
    fi
    echo -e "${CYAN}لیست تانل‌های فعال:${RESET}"
    local i=1
    while IFS='|' read -r name role local_ip remote_ip tun_local tun_peer mtu; do
        [[ -z "$name" ]] && continue
        echo "$i) $name  |  نقش: $role  |  local: $local_ip -> remote: $remote_ip  |  IP داخلی: $tun_local (peer: $tun_peer)  |  MTU: $mtu"
        i=$((i+1))
    done < "$STATE_FILE"
    return 0
}

add_tunnel() {
    echo "نقش این سرور را انتخاب کن:"
    echo "1 - IRAN"
    echo "2 - FOREIGN"
    read -p "1 یا 2: " LOCATION

    if [[ "$LOCATION" != "1" && "$LOCATION" != "2" ]]; then
        echo -e "${RED}[!] گزینه نامعتبر.${RESET}"
        return 1
    fi

    read -p "IP سرور IRAN را وارد کن: " IP_IRAN
    read -p "IP سرور FOREIGN را وارد کن: " IP_FOREIGN

    IDX=$(next_index)
    TUN_NAME="vatan-m${IDX}"

    echo "می‌خوای IP داخلی تانل (ساب‌نت /30) به‌صورت خودکار انتخاب بشه یا دستی وارد کنی؟"
    echo "1 - خودکار (پیشنهادی)"
    echo "2 - دستی (وقتی طرف مقابل قبلاً یه ساب‌نت مشخص استفاده کرده)"
    read -p "1 یا 2: " SUBNET_MODE

    if [[ "$SUBNET_MODE" == "2" ]]; then
        read -p "IP داخلی این سرور (مثلا 192.168.30.2): " TUN_LOCAL_IP
        read -p "IP داخلی سمت مقابل (peer) (مثلا 192.168.30.1): " TUN_PEER_IP
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
        echo -e "${YELLOW}[i] IP داخلی این سرور: $TUN_LOCAL_IP  |  IP داخلی سمت مقابل: $TUN_PEER_IP${RESET}"
        echo -e "${YELLOW}[i] روی سرور مقابل، حتما همین جفت آدرس رو (برعکس) وارد کن تا مچ بشه.${RESET}"
    fi

    read -p "MTU تانل را وارد کن [پیش‌فرض 1436]: " TUN_MTU
    TUN_MTU=${TUN_MTU:-1436}

    if [[ "$LOCATION" == "1" ]]; then
        echo "[*] ساخت تانل برای سرور IRAN -> $IP_FOREIGN ..."
        sudo ip tunnel add "$TUN_NAME" mode gre local "$IP_IRAN" remote "$IP_FOREIGN" ttl 255
        sudo ip link set dev "$TUN_NAME" up
        sudo ip addr add "${TUN_LOCAL_IP}/30" dev "$TUN_NAME"
        sudo ip link set dev "$TUN_NAME" mtu "$TUN_MTU"

        sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null

        read -p "می‌خوای فوروارد NAT برای این تانل (به سمت $TUN_PEER_IP) اضافه بشه؟ (y/n): " DO_NAT
        if [[ "$DO_NAT" == "y" || "$DO_NAT" == "Y" ]]; then
            sudo iptables -t nat -A PREROUTING -p tcp --dport 22 -j DNAT --to-destination "$TUN_LOCAL_IP"
            sudo iptables -t nat -A PREROUTING -j DNAT --to-destination "$TUN_PEER_IP"
            sudo iptables -t nat -A POSTROUTING -j MASQUERADE
        fi

        ROLE="IRAN"
    else
        echo "[*] ساخت تانل برای سرور FOREIGN -> $IP_IRAN ..."
        sudo ip tunnel add "$TUN_NAME" mode gre local "$IP_FOREIGN" remote "$IP_IRAN" ttl 255
        sudo ip link set dev "$TUN_NAME" up
        sudo ip addr add "${TUN_LOCAL_IP}/30" dev "$TUN_NAME"
        sudo ip link set dev "$TUN_NAME" mtu "$TUN_MTU"

        read -p "بلاک کردن ICMP ورودی برای این سرور فعال بشه؟ (y/n): " DO_ICMP
        if [[ "$DO_ICMP" == "y" || "$DO_ICMP" == "Y" ]]; then
            sudo iptables -A INPUT --proto icmp -j DROP
        fi

        ROLE="FOREIGN"
    fi

    echo "${TUN_NAME}|${ROLE}|${IP_IRAN}|${IP_FOREIGN}|${TUN_LOCAL_IP}|${TUN_PEER_IP}|${TUN_MTU}" >> "$STATE_FILE"
    echo -e "${GREEN}[+] تانل $TUN_NAME با موفقیت ساخته شد.${RESET}"

    read -p "می‌خوای همین الان یه تانل دیگه هم اضافه کنی؟ (y/n): " AGAIN
    if [[ "$AGAIN" == "y" || "$AGAIN" == "Y" ]]; then
        add_tunnel
    fi
}

delete_single_tunnel() {
    list_tunnels || return 0
    read -p "شماره تانلی که می‌خوای حذف بشه رو وارد کن (0 برای انصراف): " NUM
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
        echo -e "${RED}[!] شماره نامعتبر.${RESET}"
        return 1
    fi

    local del_name=$(echo "$target_line" | cut -d'|' -f1)
    echo "[*] حذف تانل $del_name ..."
    sudo ip link set dev "$del_name" down 2>/dev/null
    sudo ip tunnel del "$del_name" 2>/dev/null
    sudo ip link delete "$del_name" 2>/dev/null

    grep -vF "$target_line" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    echo -e "${GREEN}[+] تانل $del_name حذف شد.${RESET}"
    echo -e "${YELLOW}[i] توجه: قوانین iptables (NAT/ICMP) که دستی اضافه شده بودن رو این گزینه پاک نمی‌کنه؛ برای پاکسازی کامل از گزینه 'حذف همه' استفاده کن.${RESET}"
}

delete_all_tunnels() {
    if [[ ! -s "$STATE_FILE" ]]; then
        echo -e "${YELLOW}هیچ تانلی برای حذف وجود نداره.${RESET}"
        return 0
    fi
    read -p "مطمئنی می‌خوای همه تانل‌ها حذف بشن؟ (y/n): " CONFIRM
    [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && return 0

    while IFS='|' read -r name role local_ip remote_ip tun_local tun_peer mtu; do
        [[ -z "$name" ]] && continue
        echo "[*] حذف $name ..."
        sudo ip link set dev "$name" down 2>/dev/null
        sudo ip tunnel del "$name" 2>/dev/null
        sudo ip link delete "$name" 2>/dev/null
    done < "$STATE_FILE"

    > "$STATE_FILE"

    read -p "قوانین iptables مربوط به NAT/ICMP که این اسکریپت اضافه کرده هم پاک بشن؟ (y/n): " CLEAN_IPT
    if [[ "$CLEAN_IPT" == "y" || "$CLEAN_IPT" == "Y" ]]; then
        sudo iptables -t nat -F PREROUTING
        sudo iptables -t nat -F POSTROUTING
        sudo iptables -F INPUT
        echo -e "${YELLOW}[i] توجه: این کار همه قوانین PREROUTING/POSTROUTING/INPUT رو پاک می‌کنه، نه فقط مال این اسکریپت.${RESET}"
    fi

    echo -e "${GREEN}[+] همه تانل‌ها حذف شدند.${RESET}"
}

main_menu() {
    banner
    while true; do
        echo ""
        echo "1 - افزودن تانل جدید"
        echo "2 - نمایش لیست تانل‌ها"
        echo "3 - حذف یک تانل مشخص"
        echo "4 - حذف همه تانل‌ها"
        echo "0 - خروج"
        read -p "انتخاب کن: " CHOICE
        case "$CHOICE" in
            1) add_tunnel ;;
            2) list_tunnels ;;
            3) delete_single_tunnel ;;
            4) delete_all_tunnels ;;
            0) exit 0 ;;
            *) echo -e "${RED}[!] گزینه نامعتبر.${RESET}" ;;
        esac
    done
}

main_menu
