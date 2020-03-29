#!/usr/bin/env bash

set -euo pipefail

ECSAMI=`aws ec2 describe-images --filters 'Name=name,Values=soe-amazonlinux1-ecs*' --query 'sort_by(Images, &CreationDate)[-1].ImageId' --region ap-southeast-2 --output text`
echo "Latest ECS AMI is "$ECSAMI
aws ssm put-parameter --name "/app/nifi/ecsami" --value $ECSAMI --type String --overwrite --region ap-southeast-2  