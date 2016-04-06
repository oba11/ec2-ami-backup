#!/bin/bash -l
#
# This script backups EC2 instances to AMI from tag name
# Created By:         Oluwaseun Obajobi
# Created Date:       August 25, 2013
# Last Modified Date: August 25, 2013
#
# -t web -n 2 -cr ap-southeast-1 -dr eu-west-1 -b sunday -dn 3

TAGPREFIX=""
CREGION="ap-southeast-1"
DREGION="eu-west-1"
NUMBER="0"
DNUMBER="0"
BKPDAY=""
DATE=`date +%Y-%m-%dT%H.%M.%SZ`
DAY=`date +%a`


printhelp() {

echo "

Usage: ec2-ami-backup [OPTION]...
  -t,    --tagprefix   The AWS Tag Name, Default is Empty

  -n,    --number      The maximum number of AMIs to be left
		       
  -dn,   --dnumber     The maximum number of AMIs to be left at the DR
		       
  -cr,   --cregion     The current region to backup the AMI, Default is ${CREGION}

  -dr,   --dregion     The destination region to backup the AMI, Default is to ${DREGION}

  -b,    --backup-day  The day of the week to backup the AMI to DR region.

  -h, --help           Display help file
"

}

[ "$1" == "" ] && printhelp && exit;

while [ "$1" != "" ]; do
  case "$1" in
    -t    | --tagprefix )          TAGPREFIX=$2; shift 2 ;;
    -n    | --number )             NUMBER=$2; shift 2 ;;
    -dn   | --dnumber )            DNUMBER=$2; shift 2 ;;
    -cr   | --cregion )            CREGION=$2; shift 2 ;;
    -dr   | --dregion )            DREGION=$2; shift 2 ;;
    -b    | --backup-day )         BKPDAY=$2; shift 2 ;;
    -h    | --help )	           echo "$(printhelp)"; exit; shift; break ;;
  esac
done

BKPDAY=$(tr '[a-z]' '[A-Z]' <<< ${BKPDAY:0:1})${BKPDAY:1}
BACKUPDAY=$( echo "$BKPDAY" |cut -c -3)
LOGFILE=/var/log/ec2-ami-backup.log
AWAKEY='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
AWSKEY='BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'

let NUMBER--
if [ -z "$DNUMBER" ]; then
  let DNUMBER--
fi

$EC2_HOME/bin/ec2-describe-tags --aws-access-key=$AWAKEY --aws-secret-key=$AWSKEY --region=$CREGION \
              --filter "resource-type=instance" --filter "key=Name" --filter "value=${TAGPREFIX}*" | \
              cut -f3 > /tmp/ec2-${TAGPREFIX}-tag-list

INSTANCEIDS=(`cat /tmp/ec2-${TAGPREFIX}-tag-list`)

# Loop the Instance IDs
for INSTANCEID in `cat /tmp/ec2-${TAGPREFIX}-tag-list | sed ':a;N;$!ba;s/\n/ /g'`
do
  echo $INSTANCEID
  TAGNAME=(`ec2-describe-instances --aws-access-key=$AWAKEY --aws-secret-key=$AWSKEY --region=$CREGION \
              $INSTANCEID | grep TAG | grep Name | cut -f5`)
  echo $TAGNAME


  # Create AMI Image
  # The script still doesnt remove attached volumes for windows, weird aws
  # Read article https://forums.aws.amazon.com/message.jspa?messageID=211264
  echo "" >> $LOGFILE
  echo "$(date +'%Y-%m-%d %T'): STARTING + $TAGNAME instance backup." >> $LOGFILE
  $EC2_HOME/bin/ec2-create-image --aws-access-key=$AWAKEY --aws-secret-key=$AWSKEY --region=$CREGION \
              $INSTANCEID -n ${TAGNAME}-${DATE} -d "${TAGNAME} [${INSTANCEID}] [${DATE}]" --no-reboot \
              -b '/dev/sdf=none' -b '/dev/sdg=none' -b '/dev/sdh=none' -b '/dev/sdi=none' -b '/dev/sdj=none' \
              -b 'xvdf=none' -b 'xvdg=none' -b 'xvdh=none' -b 'xvdi=none' -b 'xvdj=none' \
              > /tmp/ec2_ami_identity

  #Saving the AMI ID of the instance backup
  C_AMI_ID=`cat /tmp/ec2_ami_identity | cut -f2`
  echo -e "$(date +'%Y-%m-%d %T'): COMPLETED + $TAGNAME instance backup as $C_AMI_ID." >> $LOGFILE


  # Delete OLD AMI leaving one
  echo -e "$(date +'%Y-%m-%d %T'): CLEANUP + Checking for old $TAGNAME AMI backup..." >> $LOGFILE
  $EC2_HOME/bin/ec2-describe-images --aws-access-key=$AWAKEY --aws-secret-key=$AWSKEY --region=$CREGION \
               | grep IMAGE | grep available | grep ${TAGNAME} | grep -v ${C_AMI_ID} | cut -f2 \
               > /tmp/ec2-$TAGNAME-ami-list

  FILELIST=(`cat /tmp/ec2-${TAGNAME}-ami-list`)
  FILECOUNT=`echo ${FILELIST[*]} | wc -w`

  if [ $FILECOUNT -gt $NUMBER ]
  then
    echo "$(date +'%Y-%m-%d %T'): CLEANUP + Old AMI found, removing ${FILELIST[0]} AMI removal from set..." >> $LOGFILE
    $EC2_HOME/bin/ec2-describe-images --aws-access-key=$AWAKEY --aws-secret-key=$AWSKEY --region=$CREGION \
               ${FILELIST[0]} | grep EBS | cut -f5 > /tmp/ec2-${FILELIST[0]}-snapshot-list

    AMI_SNAP_IDS=(`cat /tmp/ec2-${FILELIST[0]}-snapshot-list`)
    SNAPSHOT_COUNT=`echo ${AMI_SNAP_IDS[*]} | wc -w`

    #Deregistering the AMI image
    echo "$(date +'%Y-%m-%d %T'): CLEANUP + Deleting ${FILELIST[0]} AMI..." >> $LOGFILE
    $EC2_HOME/bin/ec2-deregister --aws-access-key=$AWAKEY --aws-secret-key=$AWSKEY --region=$CREGION ${FILELIST[0]}
  
    #Remove snapshots created by the AMI
    if [ $SNAPSHOT_COUNT -gt $NUMBER ]
    then
      for SNAPSHOT in `cat /tmp/ec2-${FILELIST[0]}-snapshot-list | sed ':a;N;$!ba;s/\n/ /g'`
      do
        echo "$(date +'%Y-%m-%d %T'): CLEANUP + Deleting snapshot ${SNAPSHOT} " >> $LOGFILE
        $EC2_HOME/bin/ec2-delete-snapshot --aws-access-key=$AWAKEY --aws-secret-key=$AWSKEY --region=$CREGION $SNAPSHOT
      done
    else
      $EC2_HOME/bin/ec2-delete-snapshot --aws-access-key=$AWAKEY --aws-secret-key=$AWSKEY --region=$CREGION $AMI_SNAP_IDS
    fi
    echo "$(date +'%Y-%m-%d %T'): CLEANUP + Completed ${FILELIST[0]} AMI and snapshots removal." >> $LOGFILE
  else
    echo "$(date +'%Y-%m-%d %T'): CLEANUP + No available OLD $TAGNAME found." >> $LOGFILE
  fi

  # Copying the Image
  if [ -z "$BACKUPDAY" ] || [ "$BACKUPDAY" != "$DAY" ]; then
    echo "$(date +'%Y-%m-%d %T'): No need for weekly ${TAGNAME} AMI to backup to ${DREGION} " >> $LOGFILE
  elif [ "$BACKUPDAY" == "$DAY" ]; then
    echo "$(date +'%Y-%m-%d %T'): Saving weekly ${TAGNAME} AMI to ${DREGION} " >> $LOGFILE

    #Wait for spot instance request to succeed.
    REQUIRED_STATUS="available"
    STATUS=`$EC2_HOME/bin/ec2-describe-images --aws-access-key=$AWAKEY --aws-secret-key=$AWSKEY --region=$CREGION \
               $C_AMI_ID | grep IMAGE | cut -f5`
    while [ $STATUS != $REQUIRED_STATUS ]
    do
      sleep 60
      STATUS=`$EC2_HOME/bin/ec2-describe-images --aws-access-key=$AWAKEY --aws-secret-key=$AWSKEY --region=$CREGION \
               $C_AMI_ID | grep IMAGE | cut -f5`
      echo "$(date +'%Y-%m-%d %T'): Waiting 60secs for ${TAGNAME} AMI to be available for copy " >> $LOGFILE
    done

    $EC2_HOME/bin/ec2-copy-image --aws-access-key=$AWAKEY --aws-secret-key=$AWSKEY --region=$DREGION \
               -r $CREGION -s $C_AMI_ID -n ${TAGNAME}-${DATE} -d "${TAGNAME} [${INSTANCEID}] [${DATE}]"

    #Deleting OLD AMIs from the DR Region
    $EC2_HOME/bin/ec2-describe-images --aws-access-key=$AWAKEY --aws-secret-key=$AWSKEY --region=$DREGION \
               | grep ${TAGNAME} | grep IMAGE | grep available | grep -v ${C_AMI_ID} | cut -f2 \
               > /tmp/ec2-${TAGNAME}-ami-list

    FILELIST=(`cat /tmp/ec2-${TAGNAME}-ami-list`)
    FILECOUNT=`echo ${FILELIST[*]} | wc -w`
    if [ $FILECOUNT -gt $DNUMBER ]
    then
      echo "$(date +'%Y-%m-%d %T'): Starting the ${FILELIST[0]} AMI removal from set" >> $LOGFILE
      $EC2_HOME/bin/ec2-describe-images --aws-access-key=$AWAKEY --aws-secret-key=$AWSKEY --region=$DREGION \
               ${FILELIST[0]} | grep EBS | cut -f5 > /tmp/ec2-${FILELIST[0]}-snapshot-list

      AMI_SNAP_IDS=(`cat /tmp/ec2-${FILELIST[0]}-snapshot-list`)
      SNAPSHOT_COUNT=`echo ${AMI_SNAP_IDS[*]} | wc -w`

      #Deregistering the AMI image
      echo "$(date +'%Y-%m-%d %T'): Deleting ${FILELIST[0]} AMI" >> $LOGFILE
      $EC2_HOME/bin/ec2-deregister --aws-access-key=$AWAKEY --aws-secret-key=$AWSKEY --region=$DREGION ${FILELIST[0]}
  
      #Remove snapshots created by the AMI
      if [ $SNAPSHOT_COUNT -gt $NUMBER ]
      then
        for SNAPSHOT in `cat /tmp/ec2-${FILELIST[0]}-snapshot-list | sed ':a;N;$!ba;s/\n/ /g'`
        do
          echo "$(date +'%Y-%m-%d %T'): Deleting snapshot ${SNAPSHOT} " >> $LOGFILE
          $EC2_HOME/bin/ec2-delete-snapshot --aws-access-key=$AWAKEY --aws-secret-key=$AWSKEY --region=$DREGION $SNAPSHOT
        done
      else
        $EC2_HOME/bin/ec2-delete-snapshot --aws-access-key=$AWAKEY --aws-secret-key=$AWSKEY --region=$DREGION $AMI_SNAP_IDS
      fi
      echo "$(date +'%Y-%m-%d %T'): Completed removing ${FILELIST[0]} AMI and snapshots" >> $LOGFILE
    fi
    echo "$(date +'%Y-%m-%d %T'): DONE ++ Saved weekly ${TAGNAME} AMI to ${DREGION} " >> $LOGFILE
  fi
done
