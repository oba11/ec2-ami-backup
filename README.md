ec2-ami-backup
==============

This simple bash script does Amazon EC2 AMI backup from Tag "Name". Its suitable for environments where instances are properly tagged and backup on multiple instances instead of specifying Instance ID.
You can also use this script for disaster recovery setup.

## Requirements
* Amazon EC2 CLI tool
* openjdk-6-jdk
* AWS Access key

## Usage

```
Usage: ec2-ami-backup [OPTION]...
  -t,    --tagprefix   The AWS Tag Name, Default is Empty

  -n,    --number      The maximum number of AMIs to be left
               
  -dn,   --dnumber     The maximum number of AMIs to be left at the DR
               
  -cr,   --cregion     The current region to backup the AMI, Default is ${CREGION}

  -dr,   --dregion     The destination region to backup the AMI, Default is to ${DREGION}

  -b,    --backup-day  The day of the week to backup the AMI to DR region.

  -h, --help           Display help file
```

**Without** Copying to Disaster Recovery Region

```
~:$ ec2-ami-backup -t web -n 2 -cr ap-southeast-1
```

**With** Copying to Disaster Recovery Region

```
~:$ ec2-ami-backup -t web -n 2 -cr ap-southeast-1 -dr eu-west-1 -b Sunday -dn 3
```
