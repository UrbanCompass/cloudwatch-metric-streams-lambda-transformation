BINARY_FILE_NAME ?= "bootstrap"
ZIP_FILE_NAME ?= "bootstrap.zip"
## By default, build for Linux on amd64, as that's the Lambda architecture we'll be using.
ARCH ?= "arm64"
OS ?= "linux"

## The final bucket name will consist of BUCKET_BASE_NAME and the region name, in format <BUCKET_BASE_NAME>-<region>.
BUCKET_BASE_NAME ?= "cx-cw-metrics-tags-lambda-processor"
REGIONS = us-east-1 us-east-2 us-west-1 us-west-2 af-south-1 ap-east-1 ap-south-1 ap-south-2 ap-northeast-1 ap-northeast-2 ap-northeast-3 ap-southeast-1 ap-southeast-2 ap-southeast-3 ap-southeast-4 ap-southeast-5 ap-southeast-7 ca-central-1 ca-west-1 eu-central-1 eu-central-2 eu-west-1 eu-west-2 eu-west-3 eu-north-1 eu-south-1 eu-south-2 il-central-1 me-south-1 me-central-1 mx-central-1 sa-east-1

.PHONY: publish
publish: s3-check-or-create-buckets s3-publish-function

.PHONY: package
package: mod test build zip

.PHONY: mod
mod:
	go mod tidy

.PHONY: test
test:
	go test -v ./...

.PHONY: lint
lint: fmt vet
	golangci-lint run

.PHONY: vet
vet:
	go vet ./...

.PHONY: fmt
	go fmt ./...

.PHONY: build
build:
	GOOS=${OS} GOARCH=${ARCH} CGO_ENABLED=0 go build -mod=mod -ldflags="-s -w" -o ${BINARY_FILE_NAME} .

.PHONY: zip
zip:
	zip ${ZIP_FILE_NAME} ${BINARY_FILE_NAME}

.PHONY: s3-check-or-create-buckets
s3-check-or-create-buckets:
	@{ \
	set -e ; \
	for r in $(REGIONS); do \
		echo "Checking for existence of bucket in $$r"; \
		EXISTS_RESULT=$$(aws s3api head-bucket --region $$r --bucket "${BUCKET_BASE_NAME}-$$r" 2>&1	) || true; \
		if !(echo "$$EXISTS_RESULT" | grep -q $$r); then \
			if (echo $$EXISTS_RESULT | grep -q "404"); then \
				echo "Bucket not found in $$r, creating" ; \
				if [ "$$r" = "us-east-1" ]; then \
					aws s3api create-bucket --bucket "${BUCKET_BASE_NAME}-$$r" --region $$r > /dev/null 2>&1; \
				else \
					aws s3api create-bucket --bucket "${BUCKET_BASE_NAME}-$$r" --region $$r --create-bucket-configuration LocationConstraint=$$r > /dev/null 2>&1; \
				fi; \
				aws s3api put-public-access-block --bucket "${BUCKET_BASE_NAME}-$$r" --region $$r \
					--public-access-block-configuration "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"; \
				aws s3api put-bucket-ownership-controls --bucket "${BUCKET_BASE_NAME}-$$r" --region $$r \
					--ownership-controls="Rules=[{ObjectOwnership=ObjectWriter}]"; \
				aws s3api put-bucket-acl --bucket "${BUCKET_BASE_NAME}-$$r" --region $$r --acl public-read; \
			else \
				echo "Unknown error - ${EXISTS_RESULT}  - occured in $$r, exiting" ; \
				exit 1; \
			fi; \
		fi; \
	done; \
	}

.PHONY: s3-publish-function
s3-publish-function:
	@{ \
	set -e ; \
	for r in $(REGIONS); do \
		echo "Uploading lambda function to ${BUCKET_BASE_NAME}-$$r"; \
		aws s3 cp ${ZIP_FILE_NAME} s3://${BUCKET_BASE_NAME}-$$r/${ZIP_FILE_NAME} --region $$r; \
		aws s3api put-object-acl --bucket ${BUCKET_BASE_NAME}-$$r --key ${ZIP_FILE_NAME} --acl public-read --region $$r; \
	done; \
	}

