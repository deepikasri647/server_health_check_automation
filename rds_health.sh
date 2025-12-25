#!/bin/bash
REPORT_FILE="rds_health.txt"
RDS_INSTANCE="prod-mypropertyqr"

echo "================ Daily RDS Health Report =================" > $REPORT_FILE

# Check RDS existence
aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE >/dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "RDS Instance $RDS_INSTANCE not found ❌" >> $REPORT_FILE
else
  echo "RDS Instance : $RDS_INSTANCE" >> $REPORT_FILE
  echo "------------------------------------" >> $REPORT_FILE
  
  # Get RDS Instance Details (for allocated storage)
  RDS_INFO=$(aws rds describe-db-instances \
    --db-instance-identifier $RDS_INSTANCE \
    --query 'DBInstances[0]' \
    --output json)
  
  # Status
  STATUS=$(echo "$RDS_INFO" | jq -r '.DBInstanceStatus')
  STATUS_SYM="✅"
  [ "$STATUS" != "available" ] && STATUS_SYM="❌"
  echo "Status        : $STATUS $STATUS_SYM" >> $REPORT_FILE
  
  # ---------- CPU ----------
  CPU=$(aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name CPUUtilization \
    --dimensions Name=DBInstanceIdentifier,Value=$RDS_INSTANCE \
    --statistics Average \
    --period 300 \
    --start-time $(date -u -d '10 minutes ago' +%FT%TZ) \
    --end-time $(date -u +%FT%TZ) \
    --query 'avg(Datapoints[*].Average)' \
    --output text)
  
  CPU=${CPU:-None}
  CPU_SYM="✅"
  if [ "$CPU" != "None" ]; then
    CPU_ROUNDED=$(printf "%.0f" $CPU)
    (( $(echo "$CPU > 90" | bc -l) )) && CPU_SYM="❌"
    (( $(echo "$CPU > 80 && $CPU <= 90" | bc -l) )) && CPU_SYM="⚠️"
    echo "CPU (%)       : ${CPU_ROUNDED} ${CPU_SYM}" >> $REPORT_FILE
  else
    echo "CPU (%)       : ${CPU} ${CPU_SYM}" >> $REPORT_FILE
  fi
  
  # ---------- MEMORY - Total, Used, Available ----------
  # Get allocated memory from RDS instance info
  INSTANCE_CLASS=$(echo "$RDS_INFO" | jq -r '.DBInstanceClass')
  
  # Memory mapping based on instance class (in GB)
  case $INSTANCE_CLASS in
    db.t3.micro)    MEM_TOTAL_GB=1 ;;
    db.t3.small)    MEM_TOTAL_GB=2 ;;
    db.t3.medium)   MEM_TOTAL_GB=4 ;;
    db.t3.large)    MEM_TOTAL_GB=8 ;;
    db.t3.xlarge)   MEM_TOTAL_GB=16 ;;
    db.t3.2xlarge)  MEM_TOTAL_GB=32 ;;
    db.t4g.micro)   MEM_TOTAL_GB=1 ;;
    db.t4g.small)   MEM_TOTAL_GB=2 ;;
    db.t4g.medium)  MEM_TOTAL_GB=4 ;;
    db.t4g.large)   MEM_TOTAL_GB=8 ;;
    db.m5.large)    MEM_TOTAL_GB=8 ;;
    db.m5.xlarge)   MEM_TOTAL_GB=16 ;;
    db.m5.2xlarge)  MEM_TOTAL_GB=32 ;;
    db.m5.4xlarge)  MEM_TOTAL_GB=64 ;;
    db.r5.large)    MEM_TOTAL_GB=16 ;;
    db.r5.xlarge)   MEM_TOTAL_GB=32 ;;
    db.r5.2xlarge)  MEM_TOTAL_GB=64 ;;
    *)              MEM_TOTAL_GB=0 ;;
  esac
  
  # Get freeable memory from CloudWatch
  MEMORY_FREE_BYTES=$(aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name FreeableMemory \
    --dimensions Name=DBInstanceIdentifier,Value=$RDS_INSTANCE \
    --statistics Average \
    --period 300 \
    --start-time $(date -u -d '10 minutes ago' +%FT%TZ) \
    --end-time $(date -u +%FT%TZ) \
    --query 'avg(Datapoints[*].Average)' \
    --output text)
  
  if [ ! -z "$MEMORY_FREE_BYTES" ] && [ "$MEMORY_FREE_BYTES" != "None" ] && [ "$MEM_TOTAL_GB" -gt 0 ]; then
    # Convert bytes to GB
    MEM_AVAIL_GB=$(echo "$MEMORY_FREE_BYTES" | awk '{printf "%.0f", $1/1073741824}')
    
    # Calculate used memory
    MEM_USED_GB=$((MEM_TOTAL_GB - MEM_AVAIL_GB))
    
    # Ensure non-negative
    if [ "$MEM_USED_GB" -lt 0 ]; then
      MEM_USED_GB=0
    fi
    
    # Calculate percentage
    MEM_USED_PCT=$(echo "$MEM_USED_GB $MEM_TOTAL_GB" | awk '{printf "%.0f", ($1/$2)*100}')
    
    MEM_SYM="✅"
    if [ "$MEM_USED_PCT" -gt 90 ]; then
      MEM_SYM="❌"
    elif [ "$MEM_USED_PCT" -gt 80 ]; then
      MEM_SYM="⚠️"
    fi
    
    echo "Memory Total  : ${MEM_TOTAL_GB} GB" >> $REPORT_FILE
    echo "Memory Used   : ${MEM_USED_GB} GB (${MEM_USED_PCT}%)" >> $REPORT_FILE
    echo "Memory Avail  : ${MEM_AVAIL_GB} GB ${MEM_SYM}" >> $REPORT_FILE
  else
    echo "Memory        : Data not available ⚠️" >> $REPORT_FILE
  fi
  
  # ---------- DISK - Total, Used, Available ----------
  # Get allocated storage from RDS instance info
  DISK_TOTAL_GB=$(echo "$RDS_INFO" | jq -r '.AllocatedStorage')
  
  # Get free storage space from CloudWatch
  DISK_FREE_BYTES=$(aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name FreeStorageSpace \
    --dimensions Name=DBInstanceIdentifier,Value=$RDS_INSTANCE \
    --statistics Average \
    --period 300 \
    --start-time $(date -u -d '10 minutes ago' +%FT%TZ) \
    --end-time $(date -u +%FT%TZ) \
    --query 'avg(Datapoints[*].Average)' \
    --output text)
  
  if [ ! -z "$DISK_FREE_BYTES" ] && [ "$DISK_FREE_BYTES" != "None" ] && [ "$DISK_TOTAL_GB" -gt 0 ]; then
    # Convert bytes to GB
    DISK_AVAIL_GB=$(echo "$DISK_FREE_BYTES" | awk '{printf "%.0f", $1/1073741824}')
    
    # Calculate used disk
    DISK_USED_GB=$((DISK_TOTAL_GB - DISK_AVAIL_GB))
    
    # Ensure non-negative
    if [ "$DISK_USED_GB" -lt 0 ]; then
      DISK_USED_GB=0
    fi
    
    # Calculate percentage
    DISK_USED_PCT=$(echo "$DISK_USED_GB $DISK_TOTAL_GB" | awk '{printf "%.0f", ($1/$2)*100}')
    
    DISK_SYM="✅"
    if [ "$DISK_USED_PCT" -gt 90 ]; then
      DISK_SYM="❌"
    elif [ "$DISK_USED_PCT" -gt 80 ]; then
      DISK_SYM="⚠️"
    fi
    
    echo "Disk Total    : ${DISK_TOTAL_GB} GB" >> $REPORT_FILE
    echo "Disk Used     : ${DISK_USED_GB} GB (${DISK_USED_PCT}%)" >> $REPORT_FILE
    echo "Disk Avail    : ${DISK_AVAIL_GB} GB ${DISK_SYM}" >> $REPORT_FILE
  else
    echo "Disk Info     : Data not available ⚠️" >> $REPORT_FILE
  fi
  
  # ---------- CONNECTIONS ----------
  CONN=$(aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name DatabaseConnections \
    --dimensions Name=DBInstanceIdentifier,Value=$RDS_INSTANCE \
    --statistics Average \
    --period 300 \
    --start-time $(date -u -d '10 minutes ago' +%FT%TZ) \
    --end-time $(date -u +%FT%TZ) \
    --query 'avg(Datapoints[*].Average)' \
    --output text)
  
  CONN=${CONN:-None}
  CONN_SYM="✅"
  if [ "$CONN" != "None" ]; then
    CONN_ROUNDED=$(printf "%.0f" $CONN)
    (( $(echo "$CONN > 100" | bc -l) )) && CONN_SYM="⚠️"
    echo "Connections   : ${CONN_ROUNDED} ${CONN_SYM}" >> $REPORT_FILE
  else
    echo "Connections   : ${CONN} ${CONN_SYM}" >> $REPORT_FILE
  fi
fi
  # ---------- RDS DAILY BACKUP STATUS ----------
  
  SNAPSHOTS=$(aws rds describe-db-snapshots \
    --db-instance-identifier $RDS_INSTANCE \
    --snapshot-type automated \
    --query "DBSnapshots[*].SnapshotCreateTime" \
    --output text 2>/dev/null)

  if [ -z "$SNAPSHOTS" ]; then
    echo "Automated Backups : NOT FOUND ❌" >> $REPORT_FILE
  else
    TOTAL_BACKUPS=$(echo "$SNAPSHOTS" | wc -w)

    LAST_BACKUP=$(aws rds describe-db-snapshots \
      --db-instance-identifier $RDS_INSTANCE \
      --snapshot-type automated \
      --query "reverse(sort_by(DBSnapshots,&SnapshotCreateTime))[0].SnapshotCreateTime" \
      --output text)

    TODAY=$(date -u +"%Y-%m-%d")

    if echo "$LAST_BACKUP" | grep -q "$TODAY"; then
      TODAY_STATUS="YES ✅"
    else
      TODAY_STATUS="NO ❌"
    fi

    echo "Automated Backups Enabled : YES ✅" >> $REPORT_FILE
    echo "Total Backups Available  : $TOTAL_BACKUPS" >> $REPORT_FILE
    echo "Last Backup Time         : $LAST_BACKUP" >> $REPORT_FILE
    echo "Today's Backup Taken    : $TODAY_STATUS" >> $REPORT_FILE
  fi

