#!/bin/bash 
FINAL_REPORT="daily_health_report.txt" 
DATE=$(date '+%a %b %d %H:%M:%S %Z %Y') 

echo "DAILY Server HEALTH REPORT" > $FINAL_REPORT 
echo "Date: $DATE" >> $FINAL_REPORT 
echo "" >> $FINAL_REPORT 

# Run EKS script 
./eks_health.sh 
cat eks_health_cloudwatch.txt >> $FINAL_REPORT 

echo "" >> $FINAL_REPORT 
echo "" >> $FINAL_REPORT 

#OVH Report

# Pull latest OVH report from GitHub repo
git fetch origin mypropertyqr-prod
git checkout mypropertyqr-prod
OVH_FILE=$(ls -t ovh_health_report_*.txt | head -1)  # latest file
echo "================ OVH SERVER HEALTH REPORT =================" >> $FINAL_REPORT
if [[ -f "$OVH_FILE" ]]; then
    cat "$OVH_FILE" >> $FINAL_REPORT
else
    echo "OVH report not found ❌" >> $FINAL_REPORT
fi

echo "" >> $FINAL_REPORT
echo "" >> $FINAL_REPORT

# Run RDS script 
./rds_health.sh 
cat rds_health.txt >> $FINAL_REPORT 

echo "" >> $FINAL_REPORT 
echo "" >> $FINAL_REPORT 

# Run GitHub repos script 
./github_repos.sh 
cat github_repos.txt >> $FINAL_REPORT 

echo "Report generated: $FINAL_REPORT"
