#!/usr/bin/env bash

set -euo pipefail

STACK_NAME=$1

if [[ -z "$@" ]]
then
  echo "No options supplied"
  usage
  exit 1
fi


ECS_CLUSTER="dp-nifi-nifiecs"
echo "ECS Cluster is "$ECS_CLUSTER
CONTAINER_INSTANCE=`aws ecs --region ap-southeast-2 --output text list-container-instances --cluster $ECS_CLUSTER --filter "runningTasksCount == 1" --query 'containerInstanceArns'`
echo "ECS CONTAINER INSTANCE is "$CONTAINER_INSTANCE
EC2_INSTANCE=`aws ecs --region ap-southeast-2 --output text describe-container-instances --cluster $ECS_CLUSTER --container-instances $CONTAINER_INSTANCE --query 'containerInstances[*].ec2InstanceId'`
echo "EC2 INSTANCE is "$EC2_INSTANCE
FQDN=`aws ec2 --region ap-southeast-2 --output text describe-instances --instance-id $EC2_INSTANCE --query 'Reservations[*].Instances[*].PrivateDnsName'`
echo "FQDN is "$FQDN
aws ssm put-parameter --name "/app/nifi/dp-nifi/instance" --value $FQDN --type String --overwrite --region ap-southeast-2  