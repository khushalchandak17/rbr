#!/usr/bin/env bash
# system.sh – System Information Summary (from bundle only)

hdr "SYSTEM INFORMATION"

# ------------------------------------------
# Hostname
# ------------------------------------------
HOSTNAME_STR="$(first_line_or_na "$SYSTEMINFO_DIR/hostname")"
log "Hostname" "$HOSTNAME_STR"

# ------------------------------------------
# OS Information
# ------------------------------------------
OS_PRETTY="N/A"
if [[ -f "$SYSTEMINFO_DIR/osrelease" ]]; then
    OS_PRETTY="$(grep PRETTY_NAME "$SYSTEMINFO_DIR/osrelease" 2>/dev/null \
        | head -n1 | cut -d= -f2- | tr -d '"' )"
    [[ -z "$OS_PRETTY" ]] && OS_PRETTY="N/A"
fi
log "OS" "$OS_PRETTY"

# ------------------------------------------
# Kernel Version
# ------------------------------------------
KERNEL_STR="N/A"
if [[ -f "$SYSTEMINFO_DIR/uname" ]]; then
    # typical uname output inside bundle: Linux <host> <kernel> ...
    KERNEL_STR="$(awk 'NR==1{print $3}' "$SYSTEMINFO_DIR/uname" 2>/dev/null)"
fi
log "Kernel" "$KERNEL_STR"

# ------------------------------------------
# Collection Time
# ------------------------------------------
COLLECTION_TIME="$(first_line_or_na "$SYSTEMINFO_DIR/date")"
log "Collection Time" "$COLLECTION_TIME"

# ------------------------------------------
# Uptime
# ------------------------------------------
UPTIME_LINE="$(first_line_or_na "$SYSTEMINFO_DIR/uptime")"
log "Uptime" "$UPTIME_LINE"

# ------------------------------------------
# CPU Cores
# ------------------------------------------
CPU_CORES="N/A"
if [[ -f "$SYSTEMINFO_DIR/cpuinfo" ]]; then
    CPU_CORES="$(grep -c '^processor' "$SYSTEMINFO_DIR/cpuinfo" 2>/dev/null)"
fi
log "CPU Cores" "$CPU_CORES"

# ------------------------------------------
# Load Average (1 min)
# ------------------------------------------
LOAD_1M="N/A"
if [[ -f "$SYSTEMINFO_DIR/uptime" ]]; then
    LOAD_1M="$(sed -E 's/.*load average[s]*: ([0-9., ]+).*/\1/' "$SYSTEMINFO_DIR/uptime" \
        | head -n1 | cut -d',' -f1 | tr -d ' ' )"
    [[ -z "$LOAD_1M" ]] && LOAD_1M="N/A"
fi
log "Load (1 min)" "$LOAD_1M"

# ------------------------------------------
# Root Filesystem Usage
# ------------------------------------------
ROOT_FS="N/A"
if [[ -f "$SYSTEMINFO_DIR/dfh" ]]; then
    # Expected df -h output:
    # Filesystem Size Used Avail Use% Mounted_on
    ROOT_FS="$(awk 'NR==2{print $3" / "$2" ("$5")"}' "$SYSTEMINFO_DIR/dfh" 2>/dev/null)"
    [[ -z "$ROOT_FS" ]] && ROOT_FS="N/A"
fi
log "Root FS (Collected)" "$ROOT_FS"

# ------------------------------------------
# Memory Available (MiB)
# ------------------------------------------
MEM_AVAIL="N/A"
if [[ -f "$SYSTEMINFO_DIR/freem" ]]; then
    MEM_AVAIL="$(awk 'NR==2{print $4}' "$SYSTEMINFO_DIR/freem" 2>/dev/null)"
    [[ -z "$MEM_AVAIL" ]] && MEM_AVAIL="N/A"
fi
log "Mem Available" "${MEM_AVAIL} MiB"

# ------------------------------------------
# CPU Idle %
# ------------------------------------------
CPU_IDLE="N/A"
if [[ -f "$SYSTEMINFO_DIR/top" ]]; then
    CPU_IDLE="$(grep 'Cpu' "$SYSTEMINFO_DIR/top" 2>/dev/null \
        | head -n1 \
        | awk '{for(i=1;i<=NF;i++){ if($i ~ /%id/){print $(i-1)} }}')"
    [[ -z "$CPU_IDLE" ]] && CPU_IDLE="N/A"
fi
log "CPU Idle" "${CPU_IDLE}%"

# ------------------------------------------
# Inode Usage
# ------------------------------------------
INODE_MAX=0
if [[ -f "$SYSTEMINFO_DIR/dfi" ]]; then
    INODE_MAX="$(awk 'NR>1{print $5}' "$SYSTEMINFO_DIR/dfi" | tr -d '%' | sort -nr | head -n1)"
    INODE_MAX="$(int_or_zero "$INODE_MAX")"
fi

INODE_STATUS="OK (${INODE_MAX}%)"
if (( INODE_MAX >= 80 )); then
    INODE_STATUS="CRITICAL (${INODE_MAX}%)"
elif (( INODE_MAX >= 60 )); then
    INODE_STATUS="WARNING (${INODE_MAX}%)"
fi

log "Max Inode Usage" "$INODE_STATUS"

echo ""
