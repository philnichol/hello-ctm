# get envvars from tfvars
name = $(shell grep -e name infrastructure/terraform.tfvars | cut -d '=' -f 2 | tr -d '[:space:]' | tr -d '\"')
env = $(shell grep -e env infrastructure/terraform.tfvars | cut -d '=' -f 2 | tr -d '[:space:]' | tr -d '\"')
image_tag = $(shell grep -e image_tag infrastructure/terraform.tfvars | cut -d '=' -f 2 | tr -d '[:space:]' | tr -d '\"')
region = $(shell grep -e region infrastructure/terraform.tfvars | cut -d '=' -f 2 | tr -d '[:space:]' | tr -d '\"')

# ensure requirements are installed
checkdependencies:
	which aws \
		&& which docker \
		&& which python3 \
		&& which terraform \
		|| exit 1

# ensure variables are set
checkvariables:
ifndef AWS_ACCOUNT_NUMBER
	$(error AWS_ACCOUNT_NUMBER is undefined)
endif

ifeq (, $(name))
	$(error name var not set)
endif
ifeq (, $(env))
	$(error env var not set)
endif
ifeq (, $(image_tag))
	$(error image_tag var not set)
endif

full_image_path := $(AWS_ACCOUNT_NUMBER).dkr.ecr.$(region).amazonaws.com/$(name)-$(env):$(image_tag)
repo_path := $(AWS_ACCOUNT_NUMBER).dkr.ecr.$(region).amazonaws.com

# login to ECR
codelogin:
	pushd code \
		&& aws ecr get-login-password --region $(region) | docker login --username AWS --password-stdin $(repo_path) \
		|| exit 1; \
		popd

# build docker image
codebuild:
	pushd code \
		&& docker build -t $(full_image_path) . \
		|| exit 1; \
		popd

# push docker image
codepush:
	pushd code \
		&& docker push $(full_image_path) \
		|| exit 1; \
		popd

# basic linting
tffmt:
	pushd infrastructure \
		&& terraform fmt -recursive -list=true -check=true \
		|| exit 1; \
		popd

# init terraform
tfinit:
	pushd infrastructure \
		&& terraform init --reconfigure \
		|| exit 1; \
		popd

# validate terraform
tfvalidate:
	pushd infrastructure \
		&& terraform validate \
		|| exit 1; \
		popd

# apply ECR terraform only, prompting user for confirmation
# this is ugly but required since ECR has to exist before the docker image can be pushed up
tfecrapply:
	pushd infrastructure \
		&& terraform apply -target="aws_ecr_repository.ecr" \
		|| exit 1; \
		popd

# apply terraform, prompting user for confirmation
tfapply:
	pushd infrastructure \
		&& terraform apply \
		|| exit 1; \
		popd

# destroy all terraform infrastructure, prompting user for confirmation
tfdestroy:
	pushd infrastructure \
		&& terraform destroy \
		|| exit 1; \
		popd

prep: checkdependencies checkvariables

runlocal: prep codebuild
	docker run -d -p 5000:5000 $(full_image_path)

destroy: prep tfinit tfdestroy

all: prep tffmt tfinit tfvalidate tfecrapply codelogin codebuild codepush tfapply
