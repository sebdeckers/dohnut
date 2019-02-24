# override these values at runtime as desired
# eg. make build ARCH=armhf BUILD_OPTIONS=--no-cache
ARCH := amd64
DOCKER_REPO := klutchell/dohnut
BUILD_OPTIONS +=

# these values are used for container labels at build time
BUILD_DATE := $(strip $(shell docker run --rm busybox date -u +'%Y-%m-%dT%H:%M:%SZ'))
BUILD_VERSION := $(strip $(shell git describe --tags --dirty))
VCS_REF := $(strip $(shell git rev-parse --short HEAD))
VCS_TAG := $(strip $(shell git describe --abbrev=0 --tags))
DOCKER_TAG := ${VCS_TAG}-${ARCH}

# static GOARCH to ARCH mapping (don't change these)
# supported GOARCH values can be found here: https://golang.org/doc/install/source#environment
# supported ARCH values can be found here: https://github.com/docker-library/official-images#architectures-other-than-amd64
amd64_BASE_IMAGE = amd64/node
arm_BASE_IMAGE = arm32v7/node
arm64_BASE_IMAGE = arm64v8/node
BASE_IMAGE = ${${ARCH}_BASE_IMAGE}

.DEFAULT_GOAL := build

.EXPORT_ALL_VARIABLES:

.ONESHELL:

.PHONY: qemu-user-static
qemu-user-static:
	@docker run --rm --privileged multiarch/qemu-user-static:register --reset

.PHONY: build
build: qemu-user-static
	@docker build ${BUILD_OPTIONS} \
		--build-arg BASE_IMAGE \
		--build-arg BUILD_VERSION \
		--build-arg BUILD_DATE \
		--build-arg VCS_REF \
		--tag ${DOCKER_REPO}:${DOCKER_TAG} .

.PHONY: test
test: qemu-user-static
	$(eval CONTAINER=$(shell docker run -d -p 5300:5300/tcp -p 5300:5300/udp ${DOCKER_REPO}:${DOCKER_TAG} --listen 0.0.0.0:5300 --doh commonshost))
	dig sigok.verteiltesysteme.net @127.0.0.1 -p 5300 | grep NOERROR || exit 1
	dig sigfail.verteiltesysteme.net @127.0.0.1 -p 5300 | grep SERVFAIL || exit 1
	@docker stop ${CONTAINER}
	@docker rm ${CONTAINER}

.PHONY: push
push:
	@docker push ${DOCKER_REPO}:${DOCKER_TAG}

.PHONY: manifest
manifest:
	@manifest-tool push from-args \
		--platforms linux/amd64,linux/arm,linux/arm64 \
		--template ${DOCKER_REPO}:${VCS_TAG}-ARCH \
		--target ${DOCKER_REPO}:${VCS_TAG} \
		--ignore-missing
	@manifest-tool push from-args \
		--platforms linux/amd64,linux/arm,linux/arm64 \
		--template ${DOCKER_REPO}:${VCS_TAG}-ARCH \
		--target ${DOCKER_REPO}:latest \
		--ignore-missing

.PHONY: release
release: build test push
