# Copyright 2022 Charlie Chiang
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Those variables assigned with ?= can be overridden by setting them
# manually on the command line or using environment variables.

# Use build container or local go sdk. If use have go installed, then
# we use the local go sdk by default. Set USE_BUILD_CONTAINER manually
# to use build container.
USE_BUILD_CONTAINER ?=
ifeq (, $(shell which go))
  USE_BUILD_CONTAINER := 1
endif
# Go version used as the image of the build container, grabbed from go.mod
GO_VERSION  := $(shell grep -E 'go [[:digit:]]*.[[:digit:]]*' go.mod | sed 's/go //')
# Build container image
BUILD_IMAGE ?= golang:$(GO_VERSION)-alpine

# The base image of container artifacts
BASE_IMAGE  ?= gcr.io/distroless/static:nonroot

# Set this to anything to optimize binary for debugging, otherwise for release
DEBUG       ?=

# env to passthrough to the build container
GOFLAGS     ?=
GOPROXY     ?=
HTTP_PROXY  ?=
HTTPS_PROXY ?=

# Version string, use git tag by default
VERSION     ?= $(shell git describe --tags --always --dirty)

# Container image tag, same as VERSION by default
# if VERSION is not a semantic version (e.g. local uncommitted versions), then use latest
IMAGE_TAG ?= $(shell bash -c " \
  if [[ ! $(VERSION) =~ ^v[0-9]{1,2}\.[0-9]{1,2}\.[0-9]{1,2}(-(alpha|beta)\.[0-9]{1,2})?$$ ]]; then \
    echo latest;     \
  else               \
    echo $(VERSION); \
  fi")

# Full Docker image name (e.g. docker.io/oamdev/kubetrigger:latest)
IMAGE_REPO_TAGS  ?= $(addsuffix /$(IMAGE_NAME):$(IMAGE_TAG),$(IMAGE_REPOS))

GOOS        ?=
GOARCH      ?=
# If user has not defined GOOS/GOARCH, use Go defaults.
# If user don't have Go, use the os/arch of their machine.
ifeq (, $(shell which go))
  HOSTOS     := $(shell uname -s | tr '[:upper:]' '[:lower:]')
  HOSTARCH   := $(shell uname -m)
  ifeq ($(HOSTARCH),x86_64)
    HOSTARCH := amd64
  endif
  OS         := $(if $(GOOS),$(GOOS),$(HOSTOS))
  ARCH       := $(if $(GOARCH),$(GOARCH),$(HOSTARCH))
else
  OS         := $(if $(GOOS),$(GOOS),$(shell go env GOOS))
  ARCH       := $(if $(GOARCH),$(GOARCH),$(shell go env GOARCH))
endif

# Windows have .exe in the binary name
BIN_EXTENSION :=
ifeq ($(OS), windows)
    BIN_EXTENSION := .exe
endif

# Binary basename
BIN_BASENAME     := $(BIN)$(BIN_EXTENSION)
# Binary basename with extended info, i.e. version-os-arch
BIN_VERBOSE_BASE := $(BIN)-$(VERSION)-$(OS)-$(ARCH)$(BIN_EXTENSION)
# If the user set FULL_NAME, we will use the basename with extended info
FULL_NAME        ?=
BIN_FULLNAME     := $(if $(FULL_NAME),$(BIN_VERBOSE_BASE),$(BIN_BASENAME))
# Package filename (generated by `make package'). Use zip for Windows, tar.gz for all other platforms.
PKG_FULLNAME     := $(BIN_VERBOSE_BASE).tar.gz
ifeq ($(OS), windows)
    PKG_FULLNAME := $(subst .exe,,$(BIN_VERBOSE_BASE)).zip
endif

# This holds build output and helper tools
DIST             := bin
# This holds build cache, if build container is used
GOCACHE          := .go
BIN_VERBOSE_DIR  := $(DIST)/$(BIN)-$(VERSION)
# Full output path
OUTPUT           := $(if $(FULL_NAME),$(BIN_VERBOSE_DIR)/$(BIN_FULLNAME),$(DIST)/$(BIN_FULLNAME))