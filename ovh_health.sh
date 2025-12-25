#!/bin/bash

# ================ OVH SERVER HEALTH CHECK ================
OVH_IP=${OVH_IP}
OVH_USER=${OVH_USER}
OVH_PASS=${OVH_PASS}
OUTPUT_FILE="ovh_health_report.txt"

echo "================ OVH SERVER HEALTH REPORT =================" > $OUTPUT_FILE
echo "Server       : ${OVH_IP}" >> $OUTPUT_FILE
echo "Date & Time  : $(date)" >> $OUTPUT_FILE
echo "" >> $OUTPUT_FILE


# CPU
echo "================ SYSTEM RESOURCES ================"
CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}')
CPU=$(printf "%.0f" $CPU)
echo "CPU (%)      : $CPU ✅"
echo ""

# Memory
MEM_TOTAL=$(free -g | awk '/Mem:/ {print $2}')
MEM_USED=$(free -g | awk '/Mem:/ {print $3}')
MEM_AVAIL=$(free -g | awk '/Mem:/ {print $7}')
echo "Memory Total : ${MEM_TOTAL} GB"
echo "Memory Used  : ${MEM_USED} GB"
echo "Memory Avail : ${MEM_AVAIL} GB ✅"
echo ""

# Disk
DISK_TOTAL=$(df -BG / | awk 'NR==2 {print $2}' | sed 's/G//')
DISK_USED=$(df -BG / | awk 'NR==2 {print $3}' | sed 's/G//')
DISK_AVAIL=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
echo "Disk Total   : ${DISK_TOTAL} GB"
echo "Disk Used    : ${DISK_USED} GB"
echo "Disk Avail   : ${DISK_AVAIL} GB ✅"
echo ""

# PM2 Status
echo "=================== PM2 STATUS ==================="
if command -v pm2 &> /dev/null; then
    pm2 list 2>/dev/null | head -30 || echo "PM2 command failed"
else
    echo "PM2 not installed ❌"
fi
echo ""

# Nginx Status
echo "=================== NGINX STATUS =================="
if  systemctl is-active nginx >/dev/null 2>&1; then
    echo "Nginx Status : Running ✅"
    systemctl status nginx --no-pager 2>/dev/null | grep -E "Active:|Main PID:|Memory:" | head -3
else
    echo "Nginx Status : Stopped ❌"
fi
echo ""

# Error Logs
echo "========== LAST 5 SERVER ERROR LOGS =========="
if [ -f /var/log/syslog ]; then
     grep -i "error\|fail\|critical" /var/log/syslog 2>/dev/null | tail -5 | head -5
else
    echo "No syslog file found"
fi
echo ""

# Access Logs
echo "========== LAST 5 SERVER ACCESS LOGS =========="
if [ -f /var/log/auth.log ]; then
     grep "Accepted\|session opened" /var/log/auth.log 2>/dev/null | tail -5 | head -5
else
    echo "No auth.log file found"
fi
echo ""

ENDSSH

echo "=================== REPORT END ====================" >> $OUTPUT_FILE

echo "✅ OVH health check completed - Report saved to: $OUTPUT_FILE"

