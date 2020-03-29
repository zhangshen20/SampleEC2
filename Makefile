SHELL := /bin/bash -e

.PHONY:  help  init install lock sync shell test prepare requirements stacks $(STACKS) clean clean-all clean-% \
	delete-all-stacks delete-stack-% delete-failed-stack-% deploy-all deploy-% package-all package-% build-all build-% \
	lint-% validate-% invoke-% invoke-local-% start-api-% start-lambda-%
.DEFAULT_GOAL := all

# prerequisites
# pip install --user pipenv

# Define stack prefix
STACK_PREFIX ?= datalake-l0-bestbet-

# Obtain stack suffix
ifdef BRANCH_NAME
	# Convert / and _ to - for branches like feature/new and remove master from suffix.
	STACK_SUFFIX ?= $(if $(filter-out master,$(BRANCH_NAME)),-$(subst _,-,$(subst /,-,$(BRANCH_NAME))))
else ifdef USER
	STACK_SUFFIX ?= -$(shell echo "$(USER)"| cut -d'.' -f 2)
else ifdef USERNAME
	STACK_SUFFIX ?= -$(USERNAME)
else
	STACK_SUFFIX ?=
endif

# Define AWS default region
REGION ?= ap-southeast-2

# Define default environment
ENVIRONMENT ?= dev
# ENVIRONMENT ?= prd

# Define stack names and order
STACKS ?= lambda
# iam dynamo l2bucket monitoring stepflow
# Define to any non empty value if Docker Container is required for build stage
CONTAINER ?=

# Define AWS capability
CAPABILITY ?= CAPABILITY_NAMED_IAM

# Define AWS Account
ACCOUNT ?= dh

# Define team name (for s3)
TEAM ?= endor

# Define profile 
PROFILE ?= dh-dev
# PROFILE ?= dh-prd

NO_VERIFY_SSL ?=

# --- DO NOT MODIFY AFTER THIS LINE UNTIL YOU KNOW WHAT YOU ARE DOING ---

# Paths defenition
SOURCE_PATH ?= lambdas
BUILD_PATH ?= build
CONFIG_PATH ?= cloudformation
PACKAGE_PATH ?= ${BUILD_PATH}/package
TAGS_PATH ?= ${CONFIG_PATH}/tags
PARAMETERS_PATH ?= ${CONFIG_PATH}/parameters
SAM_TEMPLATE_PATH ?= ${CONFIG_PATH}/templates

VENV ?= venv
VENV_BIN ?= $(VENV)/bin

# Files definition
TAGS_FILE ?= ${TAGS_PATH}/tags.yaml
REQUIREMENTS_FILE ?= requirements.txt
DEV_REQUIREMENTS_FILE ?= requirements-dev.txt

# Define git repo
GIT_BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
GIT_SHORT_HASH := $(shell git rev-parse --short HEAD)

# Function to generate stack name
# get-stack-name=${STACK_PREFIX}$(1)${STACK_SUFFIX}
get-stack-name=${STACK_PREFIX}$(1)

# Function to generate lambda bucker
get-lambda-s3-bucket=aws-sam-cli-managed-default-samclisourcebucket-cf3ls6ccdd5d
# get-lambda-s3-bucket=aws-sam-cli-managed-default-samclisourcebucket-prd-cf3ls6ccdd5d

# Function to generate lambda s3 prefix
get-lambda-s3-object-prefix=${TEAM}/${ACCOUNT}/${STACK_PREFIX}$(1)${STACK_SUFFIX}/${ENVIRONMENT}/${GIT_BRANCH}

# Function to generate tags from a tags file
get-tags=$(if $(wildcard ${TAGS_FILE}),--tags $(shell ${TAGS_FILE} | grep -v ^# | grep ":" | sed 's/: \(.*\)/="\1"/' | tr '\n' ' '))

# Function to generate parameters from a parameters file
get-parameters=--parameter-overrides 'ParameterKey=StackPrefix,ParameterValue=${STACK_PREFIX} ParameterKey=StackSuffix,ParameterValue=${STACK_SUFFIX} ParameterKey=Account,ParameterValue=${ACCOUNT} ParameterKey=Environment,ParameterValue=${ENVIRONMENT}$(if $(wildcard ${PARAMETERS_PATH}/${ENVIRONMENT}/$(1).yaml), $(shell yq -r 'to_entries|map("ParameterKey=\(.key),ParameterValue=\(.value|tojson)")|join(" ")' ${PARAMETERS_PATH}/${ENVIRONMENT}/$(1).yaml))'

# Function to get enviroment variabled for sam deploy
get-environment=--parameter-overrides StackPrefix=${STACK_PREFIX} StackSuffix=${STACK_SUFFIX} Account=${ACCOUNT} Environment=${ENVIRONMENT}$(if $(wildcard ${PARAMETERS_PATH}/${ENVIRONMENT}/$(1).yaml), $(shell yq -r 'to_entries|map("\(.key)=\(.value|tojson)")|join(" ")' ${PARAMETERS_PATH}/${ENVIRONMENT}/$(1).yaml))

# Function to get stack status
get-stack-status=$(shell (aws cloudformation describe-stacks --stack-name ${STACK_PREFIX}$(1)${STACK_SUFFIX} 2> /dev/null)| jq -r '.Stacks[0].StackStatus')

# Function to delete stack
delete-stack=@aws cloudformation delete-stack --stack-name ${STACK_PREFIX}$(1)${STACK_SUFFIX}

define get-tags
  $(shell cat cloudformation/tags/tags.yaml | grep -v ^# | grep ":" |  sed 's/: \(.*\)/="\1"/' | tr '\r' ' ')
	# cat cloudformation/tags/tags.yaml | grep -v ^# | grep ":"  | sed 's/: \(.*\)/="\1"/' | tr '\r' ' ' | tr '\n' ' ' | sed 's/ "/"/g'
endef

# Parameters
# ${1} = ENVIRONMENT (dev|stg|prd)
define get-build-params
  $(shell cat ${PARAMETERS_PATH}/${ENVIRONMENT}/$(1).yaml | grep -v ^# | grep -v ^--- | awk -F:\  '{print "ParameterKey="$$1",ParameterValue="$$2}' | tr '\n' ' ')
endef

define get-deploy-params
  $(shell cat ${PARAMETERS_PATH}/${ENVIRONMENT}/$(1).yaml | grep -v ^# | grep ":" | sed 's/: \(.*\)/="\1"/' | tr '\n' ' ')
endef

# Rules

venv:
	@echo "--- make venv"
	python3 --version
	python3 -m venv venv
	$(VENV_BIN)/pip install -Ur requirements.txt
	@echo""; echo Activate your venv by running \'source venv/bin/activate\'
	source venv/bin/activate

all: install test stacks ## Make all

help: ## Print help message
	@awk -F ':|##' '/^[^\t].+?:.*?##/ {printf "%-30s %s\n", $$1, $$NF}' $(MAKEFILE_LIST)

venv-clean:
	@echo "--- make venv-clean"
	rm -rf $(VENV)

clean: ## Cleans the project folder
	@echo "--- make clean"
	$(MAKE) venv-clean
	find . -name \*.py[oc] -exec rm -r {} \;
	rm -rf serverless-output.yaml
	rm -rf build/*

update-service: ## Update NIFI ECS Service
	@echo "--- update ecs service desired task count to 3"
	scripts/update-service.sh -s "dp-nifi-nifiecs"
	sleep 10
	aws ecs update-service --cluster "dp-nifi-nifiecs" --service "dp-nifi-nifiecs" --desired-count 3

find-ami: ## Find Latest AMI published in dp-dev
	@echo "--- get latest ami ---"
	scripts/get-latest-ami.sh

clean-all: $(STACKS:%=clean-%) ## Clean all stacks local folders

build-all: $(STACKS:%=build-%) ## Build all stacks

package-all: $(STACKS:%=package-%) ## Package all stacks

deploy-all: $(STACKS:%=deploy-%) ## Deploy all stacks to AWS

delete-all-stacks: $(STACKS:%=delete-stack-%) ## Delete all stacks from AWS

stacks: $(STACKS) ## Deploy all stacks AWS (alias for deploy-all)
	@echo All stacks has been created successfully

$(STACKS): % : deploy-% ## Deploy a stack with specific name
	@echo Stack $(call get-stack-name,$*) has been created successfully

deploy-%: # Deploy the stack with specific name
	@echo Deploying stack $(call get-stack-name,$*)
	# --tags $(call get-tags) 
	# --tags CostCentre="DataPlatform" Project="BestBet" Description="BestBetTippings" User="cdpsupportteam@sportsbet.com.au" DataClassification="Confidential"
	sam deploy \
		--template-file ${BUILD_PATH}/$*/package.yaml \
		--region ${REGION} \
		--stack-name $(call get-stack-name,$*) \
		--capabilities ${CAPABILITY} \
		--no-fail-on-empty-changeset \
		--parameter-overrides StackPrefix=${STACK_PREFIX} StackSuffix=${STACK_SUFFIX} Account=${ACCOUNT} Environment=${ENVIRONMENT} $(call get-deploy-params,$*)

package-%: # Create a stack package and copy lambda code to s3
	@echo Packaging stack: $(call get-stack-name,$*)
	sam package \
		--template-file ${BUILD_PATH}/$*/template.yaml \
		--output-template-file ${BUILD_PATH}/$*/package.yaml \
		--s3-bucket $(call get-lambda-s3-bucket) \
		--s3-prefix $(call get-lambda-s3-object-prefix,$*)

build-%: # requirements lint-% clean-% ## Build the stack locally
	@echo Building stack: $(call get-stack-name,$*)
	pwd
	ls -l
	sam --version
	sam build \
		$(if ${CONTAINER},--use-container) \
		--build-dir ${BUILD_PATH}/$* \
		--base-dir . \
		--manifest ${REQUIREMENTS_FILE} \
		--template ${SAM_TEMPLATE_PATH}/$*.yaml \
		--parameter-overrides 'ParameterKey=StackPrefix,ParameterValue=${STACK_PREFIX} ParameterKey=StackSuffix,ParameterValue=${STACK_SUFFIX} ParameterKey=Account,ParameterValue=${ACCOUNT} ParameterKey=Environment,ParameterValue=${ENVIRONMENT} $(call get-build-params,$*)'

clean-%: ## Delete the stack build folder
	@echo Cleaning local stack: $(call get-stack-name,$*)
	@pipenv run rm -rf ${BUILD_PATH}/$*

delete-stack-%: ## Delete stack from AWS
	@echo Deleting stack: $(call get-stack-name,$*)
	${call delete-stack,$*}

delete-failed-stack-%: ## Delete the stack if it is ROLLBACK_COMPLETE state
	$(if $(findstring ROLLBACK_COMPLETE, ${call get-stack-status,$*}), $(call delete-stack,$*), @echo -n)