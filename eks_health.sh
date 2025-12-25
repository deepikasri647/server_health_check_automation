#!/bin/bash
# ==================== CONFIG ====================
REPORT_FILE="eks_health_cloudwatch.txt"
NAMESPACE="mypropertyqr-prod"
INGRESS_NS="ingress-prod-nginx"

# ==================== HEADER ====================
echo "================ Daily EKS Health Report =================" > $REPORT_FILE
echo "Date & Time : $(date -u)" >> $REPORT_FILE

# Variable to track overall health
OVERALL_STATUS="HEALTHY ✅"

# ==================== INSTANCE TO NODE MAPPING ====================
declare -A INSTANCE_TO_NODE
INSTANCE_TO_NODE["i-020fad329526da094"]="ip-192-31-1-157.ap-south-1.compute.internal"
INSTANCE_TO_NODE["i-09fc5f02262715519"]="ip-192-31-0-122.ap-south-1.compute.internal"
INSTANCE_TO_NODE["i-05967c54024aab918"]="ip-192-31-2-116.ap-south-1.compute.internal"

# ==================== GET KUBECTL METRICS ====================
# Get node metrics once and store
KUBECTL_METRICS=$(kubectl top nodes --no-headers 2>/dev/null)

# ==================== EKS NODES ====================
INSTANCES=("i-020fad329526da094" "i-09fc5f02262715519" "i-05967c54024aab918")

for INSTANCE_ID in "${INSTANCES[@]}"; do
    NODE_NAME="${INSTANCE_TO_NODE[$INSTANCE_ID]}"
    
    echo "" >> $REPORT_FILE
    echo "Node Instance : $INSTANCE_ID" >> $REPORT_FILE
    echo "Node Name     : $NODE_NAME" >> $REPORT_FILE
    echo "------------------------------------" >> $REPORT_FILE
    
    # ---------- CPU (from CloudWatch) ----------
    CPU=$(aws cloudwatch get-metric-statistics \
      --namespace AWS/EC2 \
      --metric-name CPUUtilization \
      --dimensions Name=InstanceId,Value=$INSTANCE_ID \
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
        (( $(echo "$CPU > 90" | bc -l) )) && CPU_SYM="❌" && OVERALL_STATUS="UNHEALTHY 🔴"
        (( $(echo "$CPU > 80 && $CPU <= 90" | bc -l) )) && CPU_SYM="⚠️"
        echo "CPU (%)       : ${CPU_ROUNDED} ${CPU_SYM}" >> $REPORT_FILE
    else
        echo "CPU (%)       : ${CPU} ${CPU_SYM}" >> $REPORT_FILE
    fi
    
    # ---------- MEMORY - Total, Used, Available ----------
    NODE_INFO=$(kubectl describe node "$NODE_NAME" 2>/dev/null)
    
    if [ -n "$KUBECTL_METRICS" ] && [ -n "$NODE_INFO" ]; then
        NODE_METRIC=$(echo "$KUBECTL_METRICS" | grep "$NODE_NAME")
        
        if [ -n "$NODE_METRIC" ]; then
            # Get memory capacity (total) from node info in Mi
            MEM_CAPACITY_MI=$(echo "$NODE_INFO" | grep -A 10 "^Capacity:" | grep "memory:" | awk '{print $2}' | tr -d 'Mi' | tr -d 'Ki' | tr -d 'Gi')
            
            # Convert to GB if needed
            if echo "$NODE_INFO" | grep -A 10 "^Capacity:" | grep "memory:" | grep -q "Gi"; then
                MEM_CAPACITY_GB=$(echo "$MEM_CAPACITY_MI" | awk '{printf "%.0f", $1}')
            elif echo "$NODE_INFO" | grep -A 10 "^Capacity:" | grep "memory:" | grep -q "Ki"; then
                MEM_CAPACITY_GB=$(echo "$MEM_CAPACITY_MI" | awk '{printf "%.0f", $1/1048576}')
            else
                # Assuming Mi
                MEM_CAPACITY_GB=$(echo "$MEM_CAPACITY_MI" | awk '{printf "%.0f", $1/1024}')
            fi
            
            # Get used memory from kubectl top (in Mi)
            MEM_USED_MI=$(echo "$NODE_METRIC" | awk '{print $4}' | tr -d 'Mi')
            MEM_USED_GB=$(echo "$MEM_USED_MI" | awk '{printf "%.0f", $1/1024}')
            
            # Calculate available
            MEM_AVAILABLE_GB=$((MEM_CAPACITY_GB - MEM_USED_GB))
            
            # Calculate percentage
            MEM_USED_PCT=$(echo "$MEM_USED_GB $MEM_CAPACITY_GB" | awk '{printf "%.0f", ($1/$2)*100}')
            
            MEM_SYM="✅"
            if [ "$MEM_USED_PCT" -gt 90 ]; then
                MEM_SYM="❌"
                OVERALL_STATUS="UNHEALTHY 🔴"
            elif [ "$MEM_USED_PCT" -gt 80 ]; then
                MEM_SYM="⚠️"
            fi
            
            echo "Memory Total  : ${MEM_CAPACITY_GB} GB" >> $REPORT_FILE
            echo "Memory Used   : ${MEM_USED_GB} GB (${MEM_USED_PCT}%)" >> $REPORT_FILE
            echo "Memory Avail  : ${MEM_AVAILABLE_GB} GB ${MEM_SYM}" >> $REPORT_FILE
        else
            echo "Memory        : Node metrics unavailable ⚠️" >> $REPORT_FILE
        fi
    else
        echo "Memory        : kubectl metrics unavailable ⚠️" >> $REPORT_FILE
    fi
    
    # ---------- DISK - Total, Used, Available (Using JSON parsing) ----------
    # Get raw values from JSON
    DISK_CAPACITY_RAW=$(kubectl get node "$NODE_NAME" -o jsonpath='{.status.capacity.ephemeral-storage}' 2>/dev/null)
    DISK_ALLOCATABLE_RAW=$(kubectl get node "$NODE_NAME" -o jsonpath='{.status.allocatable.ephemeral-storage}' 2>/dev/null)
    
    if [ -n "$DISK_CAPACITY_RAW" ] && [ -n "$DISK_ALLOCATABLE_RAW" ]; then
        # Process Capacity (usually has "Ki" suffix)
        if echo "$DISK_CAPACITY_RAW" | grep -q "Ki$"; then
            DISK_CAPACITY_NUM=$(echo "$DISK_CAPACITY_RAW" | sed 's/Ki$//')
            DISK_CAPACITY_GB=$(echo "$DISK_CAPACITY_NUM" | awk '{printf "%.0f", $1/1048576}')
        else
            # No suffix - treat as bytes
            DISK_CAPACITY_GB=$(echo "$DISK_CAPACITY_RAW" | awk '{printf "%.0f", $1/1073741824}')
        fi
        
        # Process Allocatable (usually NO suffix - raw bytes)
        if echo "$DISK_ALLOCATABLE_RAW" | grep -q "Ki$"; then
            DISK_ALLOCATABLE_NUM=$(echo "$DISK_ALLOCATABLE_RAW" | sed 's/Ki$//')
            DISK_ALLOCATABLE_GB=$(echo "$DISK_ALLOCATABLE_NUM" | awk '{printf "%.0f", $1/1048576}')
        else
            # No suffix - treat as bytes
            DISK_ALLOCATABLE_GB=$(echo "$DISK_ALLOCATABLE_RAW" | awk '{printf "%.0f", $1/1073741824}')
        fi
        
        # Validate reasonable disk size (10 GB to 1000 GB)
        if [ "$DISK_CAPACITY_GB" -ge 10 ] && [ "$DISK_CAPACITY_GB" -le 1000 ]; then
            # Calculate used
            DISK_USED_GB=$((DISK_CAPACITY_GB - DISK_ALLOCATABLE_GB))
            
            # Ensure non-negative
            if [ "$DISK_USED_GB" -lt 0 ]; then
                DISK_USED_GB=0
            fi
            
            # Calculate percentage
            DISK_USED_PCT=$(echo "$DISK_USED_GB $DISK_CAPACITY_GB" | awk '{printf "%.0f", ($1/$2)*100}')
            
            DISK_SYM="✅"
            if [ "$DISK_USED_PCT" -gt 90 ]; then
                DISK_SYM="❌"
                OVERALL_STATUS="UNHEALTHY 🔴"
            elif [ "$DISK_USED_PCT" -gt 80 ]; then
                DISK_SYM="⚠️"
            fi
            
            echo "Disk Total    : ${DISK_CAPACITY_GB} GB" >> $REPORT_FILE
            echo "Disk Used     : ${DISK_USED_GB} GB (${DISK_USED_PCT}%)" >> $REPORT_FILE
            echo "Disk Avail    : ${DISK_ALLOCATABLE_GB} GB ${DISK_SYM}" >> $REPORT_FILE
        else
            echo "Disk Info     : Size out of range (${DISK_CAPACITY_GB} GB) ⚠️" >> $REPORT_FILE
        fi
    else
        echo "Disk Info     : Not available ⚠️" >> $REPORT_FILE
    fi
    
    # ---------- NETWORK ----------
    NETIN=$(aws cloudwatch get-metric-statistics \
      --namespace AWS/EC2 \
      --metric-name NetworkIn \
      --dimensions Name=InstanceId,Value=$INSTANCE_ID \
      --statistics Sum \
      --period 300 \
      --start-time $(date -u -d '10 minutes ago' +%FT%TZ) \
      --end-time $(date -u +%FT%TZ) \
      --query 'avg(Datapoints[*].Sum)' \
      --output text)
    
    NETIN=${NETIN:-0.0}
    NETIN_ROUNDED=$(printf "%.0f" $NETIN)
    echo "Network In    : ${NETIN_ROUNDED} bytes ✅" >> $REPORT_FILE
done

# ==================== EKS APP STATUS ====================
echo "" >> $REPORT_FILE
echo "================ EKS APP STATUS =================" >> $REPORT_FILE

# Get running pods count
RUNNING=$(kubectl get pods -n $NAMESPACE --no-headers 2>/dev/null | grep -c Running)
RUNNING=${RUNNING:-0}

# Get failed/error pods count
FAILED=$(kubectl get pods -n $NAMESPACE --no-headers 2>/dev/null | grep -vE 'Running|Completed' | wc -l)
FAILED=${FAILED:-0}

# Get total pods count
TOTAL=$(kubectl get pods -n $NAMESPACE --no-headers 2>/dev/null | wc -l)
TOTAL=${TOTAL:-0}

echo "Namespace     : $NAMESPACE" >> $REPORT_FILE
echo "Pods Running  : $RUNNING/$TOTAL" >> $REPORT_FILE
echo "Pods Failed   : $FAILED $( [[ $FAILED -eq 0 ]] && echo '✅' || echo '❌' )" >> $REPORT_FILE

# Show pod details if there are any issues
if [ $FAILED -gt 0 ]; then
    echo "" >> $REPORT_FILE
    echo "Failed/Problem Pods:" >> $REPORT_FILE
    kubectl get pods -n $NAMESPACE --no-headers 2>/dev/null | grep -vE 'Running|Completed' >> $REPORT_FILE
    OVERALL_STATUS="UNHEALTHY 🔴"
fi

# Show all pod status summary
echo "" >> $REPORT_FILE
echo "All Pods Status:" >> $REPORT_FILE
kubectl get pods -n $NAMESPACE -o wide 2>/dev/null >> $REPORT_FILE

# ==================== OVERALL STATUS ====================
echo "" >> $REPORT_FILE
echo "================ OVERALL STATUS =================" >> $REPORT_FILE
echo "Status        : $OVERALL_STATUS" >> $REPORT_FILE

echo "" >> $REPORT_FILE

