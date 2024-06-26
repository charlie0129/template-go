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

all: build

# ===== BUILD =====

build-dirs:
	mkdir -p "$(GOCACHE)/gocache" \
	         "$(GOCACHE)/gomodcache"
	mkdir -p "$(BIN_OUTPUT_DIR)"

build: # @HELP (default) build binary for current platform
build: gen-dockerignore build-dirs
ifeq (1, $(USE_BUILD_CONTAINER))
	echo "# BUILD using build container: $(BUILD_IMAGE)"
	docker run                                     \
	    -i                                         \
	    --rm                                       \
	    --network host                             \
	    -u $$(id -u):$$(id -g)                     \
	    -v $$(pwd):/src                            \
	    -w /src                                    \
	    -v $$(pwd)/$(GOCACHE):/cache               \
	    --env GOCACHE="/cache/gocache"             \
	    --env GOMODCACHE="/cache/gomodcache"       \
	    --env ARCH="$(ARCH)"                       \
	    --env OS="$(OS)"                           \
	    --env VERSION="$(VERSION)"                 \
	    --env GIT_COMMIT="$(GIT_COMMIT)"           \
	    --env DEBUG="$(DEBUG)"                     \
	    --env OUTPUT="$(OUTPUT)"                   \
	    --env GOFLAGS="$(GOFLAGS)"                 \
	    --env GOPROXY="$(GOPROXY)"                 \
	    --env GOPRIVATE="$(GOPRIVATE)"             \
	    --env HTTP_PROXY="$(HTTP_PROXY)"           \
	    --env HTTPS_PROXY="$(HTTPS_PROXY)"         \
	    --env GIT_CREDENTIALS="$(GIT_CREDENTIALS)" \
	    $(BUILD_IMAGE)                             \
	    ./build/build.sh $(ENTRY)
else
	echo "# BUILD using local go sdk: $(LOCAL_GO_VERSION) , set USE_BUILD_CONTAINER=1 to use containerized build environment"
	ARCH="$(ARCH)"                   \
	    OS="$(OS)"                   \
	    OUTPUT="$(OUTPUT)"           \
	    VERSION="$(VERSION)"         \
	    GIT_COMMIT="$(GIT_COMMIT)"   \
	    GOFLAGS="$(GOFLAGS)"         \
	    GOPROXY="$(GOPROXY)"         \
	    GOPRIVATE="$(GOPRIVATE)"     \
	    DEBUG="$(DEBUG)"             \
	    HTTP_PROXY="$(HTTP_PROXY)"   \
	    HTTPS_PROXY="$(HTTPS_PROXY)" \
	    bash build/build.sh $(ENTRY)
endif
ifeq (1, $(FORCE_COPY_BINARY))
	echo "# BUILD copying $(OUTPUT) to $(DIST)/$(BIN_BASENAME)"
	rm -f "$(DIST)/$(BIN_BASENAME)" && cp -f "$(OUTPUT)" "$(DIST)/$(BIN_BASENAME)"
else
	echo "# BUILD linking $(DIST)/$(BIN_BASENAME) <==> $(OUTPUT)"
	rm -f "$(DIST)/$(BIN_BASENAME)" && ln -snf "$(subst $(DIST)/,,$(OUTPUT))" "$(DIST)/$(BIN_BASENAME)"
endif

# INTERNAL: build-<os>_<arch> to build for a specific platform
build-%:
	$(MAKE) -f $(firstword $(MAKEFILE_LIST)) \
	    build                                \
	    --no-print-directory                 \
	    GOOS=$(firstword $(subst _, ,$*))    \
	    GOARCH=$(lastword $(subst _, ,$*))

all-build: # @HELP build binaries for all platforms
all-build: $(addprefix build-, $(subst /,_, $(BIN_PLATFORMS)))

# ===== PACKAGE =====

package: # @HELP build and package binary for current platform
package: build
	mkdir -p "$(PKG_OUTPUT_DIR)"
	cp -f LICENSE "$(DIST)/LICENSE" || true
	echo "# PACKAGE compressing $(OUTPUT) to $(PKG_OUTPUT)"
	$(RM) "$(PKG_OUTPUT)"
	if [ "$(OS)" == "windows" ]; then \
	    zip "$(PKG_OUTPUT)" -j "$(DIST)/$(BIN_BASENAME)" "$(DIST)/LICENSE"; \
	else \
	    tar -hczf "$(PKG_OUTPUT)" -C "$(DIST)" "$(BIN_BASENAME)" LICENSE; \
	fi;
	cd "$(PKG_OUTPUT_DIR)" && sha256sum "$(PKG_FULLNAME)" >> "$(CHECKSUM_FULLNAME)";
	echo "# PACKAGE checksum saved to $(PKG_OUTPUT_DIR)/$(CHECKSUM_FULLNAME)"
	echo "# PACKAGE linking $(DIST)/$(BIN)-packages-latest <==> $(PKG_OUTPUT_DIR)"
	ln -snf "$(BIN)-$(VERSION)/packages" "$(DIST)/$(BIN)-packages-latest"

# INTERNAL: package-<os>_<arch> to build and package for a specific platform
package-%:
	$(MAKE) -f $(firstword $(MAKEFILE_LIST)) \
	    package                              \
	    --no-print-directory                 \
	    GOOS=$(firstword $(subst _, ,$*))    \
	    GOARCH=$(lastword $(subst _, ,$*))

all-package: # @HELP build and package binaries for all platforms
all-package: $(addprefix package-, $(subst /,_, $(BIN_PLATFORMS)))
# overwrite previous checksums
	cd "$(PKG_OUTPUT_DIR)" && shopt -s nullglob && \
	    sha256sum *.{tar.gz,zip} > "$(CHECKSUM_FULLNAME)"
	echo "# PACKAGE all checksums saved to $(PKG_OUTPUT_DIR)/$(CHECKSUM_FULLNAME)"

# ===== CONTAINERS =====

container: # @HELP build container image for current platform
container: container-build
container-build: build-linux_$(ARCH) gen-dockerfile
	printf "# CONTAINER tag: %s\tname: %s\trepos: %s\tarch: %s\n" "$(IMAGE_TAGS)" "$(IMAGE_NAME)" "$(IMAGE_REPOS)" "linux/$(ARCH)"
	if [ "$(OS)" != "linux" ]; then \
	    echo "# CONTAINER warning: container target os $(OS) is not valid, only linux is allowed and will be used"; \
	fi; \
	DOCKER_BUILDKIT=1                          \
	    docker build                           \
	    -f Dockerfile.tmp                      \
	    --build-arg "ARCH=$(ARCH)"             \
	    --build-arg "OS=linux"                 \
	    --build-arg "VERSION=$(VERSION)"       \
	    --build-arg "BASE_IMAGE=$(BASE_IMAGE)" \
	    $(addprefix -t ,$(IMAGE_REPO_TAGS)) .

container-push: # @HELP push built container image to all repos
container-push: $(addprefix container-push-, $(subst :,=, $(subst /,_, $(IMAGE_REPO_TAGS))))

# INTERNAL: container-push-example.com_library_name=tag to push a specific image
container-push-%:
	echo "# Pushing $(subst =,:,$(subst _,/,$*))"
	docker push $(subst =,:,$(subst _,/,$*))

BUILDX_PLATFORMS := $(shell echo "$(IMAGE_PLATFORMS)" | sed 's/ /,/g')

all-container-push: # @HELP build and push container images for all platforms
all-container-push: $(addprefix build-, $(subst /,_, $(IMAGE_PLATFORMS))) gen-dockerfile
	printf "# CONTAINER tags: %s\tname: %s\trepos: %s\tarch: %s\n" "$(IMAGE_TAGS)" "$(IMAGE_NAME)" "$(IMAGE_REPOS)" "$(IMAGE_PLATFORMS)"
	docker buildx build --push                 \
	    -f Dockerfile.tmp                      \
	    --platform "$(BUILDX_PLATFORMS)"       \
	    --build-arg "VERSION=$(VERSION)"       \
	    --build-arg "BASE_IMAGE=$(BASE_IMAGE)" \
	    $(addprefix -t ,$(IMAGE_REPO_TAGS)) .

# ===== MISC =====

# Optional variable to pass arguments to sh
# Example: make shell CMD="-c 'date'"
CMD ?=

shell: # @HELP launch a shell in the build container
shell: build-dirs
	echo "# launching a shell in the build container"
	docker run                                     \
	    -it                                        \
	    --rm                                       \
	    --network host                             \
	    -u $$(id -u):$$(id -g)                     \
	    -v $$(pwd):/src                            \
	    -w /src                                    \
	    -v $$(pwd)/$(GOCACHE):/cache               \
	    --env GOCACHE="/cache/gocache"             \
	    --env GOMODCACHE="/cache/gomodcache"       \
	    --env ARCH="$(ARCH)"                       \
	    --env OS="$(OS)"                           \
	    --env VERSION="$(VERSION)"                 \
	    --env GIT_COMMIT="$(GIT_COMMIT)"           \
	    --env DEBUG="$(DEBUG)"                     \
	    --env OUTPUT="$(OUTPUT)"                   \
	    --env GOFLAGS="$(GOFLAGS)"                 \
	    --env GOPROXY="$(GOPROXY)"                 \
	    --env GOPRIVATE="$(GOPRIVATE)"             \
	    --env HTTP_PROXY="$(HTTP_PROXY)"           \
	    --env HTTPS_PROXY="$(HTTPS_PROXY)"         \
	    --env GIT_CREDENTIALS="$(GIT_CREDENTIALS)" \
	    $(BUILD_IMAGE)                             \
	    /bin/sh $(CMD)

# Generate a dockerignore file to ignore everything except
# current build output directory. This is useful because
# when building a container, we only need the final binary.
# So we can avoid copying unnecessary files to the build
# context.
gen-dockerignore:
	echo -e "*\n!$(BIN_OUTPUT_DIR)" > .dockerignore

gen-dockerfile:
	cat Dockerfile.in |                     \
	    sed -e 's|{BIN}|$(BIN)|g' |         \
	    sed -e 's|{VERSION}|$(VERSION)|g' | \
	    sed -e 's|{BIN_OUTPUT_DIR}|$(BIN_OUTPUT_DIR)|g' > Dockerfile.tmp

clean: # @HELP clean built binaries
clean:
	$(RM) -r $(DIST)/$(BIN)*

all-clean: # @HELP clean built binaries, build cache, and helper tools
all-clean: clean
	test -d $(GOCACHE) && chmod -R u+w $(GOCACHE) || true
	$(RM) -r $(GOCACHE) $(DIST)

version: # @HELP output the version string
version:
	echo $(VERSION)

imageversion: # @HELP output the container image version
imageversion:
	echo $(IMAGE_TAGS)

binaryname: # @HELP output current artifact binary name
binaryname:
	echo $(BIN_FULLNAME)

buildimage: # @HELP output current build image
buildimage:
	echo $(BUILD_IMAGE)

variables: # @HELP print makefile variables
variables:
	echo "BUILD:"
	echo "  build_output             $(OUTPUT)"
	echo "  app_version              $(VERSION)"
	echo "  git_commit               $(GIT_COMMIT)"
	echo "  debug_build_enabled      $(DEBUG)"
	echo "  use_build_container      $(USE_BUILD_CONTAINER)"
	echo "  build_container_image    $(BUILD_IMAGE)"
	echo "  local_go_sdk             $(LOCAL_GO_VERSION)"
	echo "CONTAINER:"
	echo "  container_base_image     $(BASE_IMAGE)"
	echo "  container_img_tags       $(IMAGE_TAGS)"
	echo "  container_img_name       $(IMAGE_NAME)"
	echo "  container_repos          $(IMAGE_REPOS)"
	echo "  container_img_full       $(IMAGE_REPO_TAGS)"
	echo "PLATFORM:"
	echo "  current_os               $(OS)"
	echo "  current_arch             $(ARCH)"
	echo "  all_bin_os_arch          $(BIN_PLATFORMS)"
	echo "  all_container_os_arch    $(IMAGE_PLATFORMS)"
	echo "ENVIRONMENTS:"
	echo "  GOPROXY                  $(GOPROXY)"
	echo "  GOPRIVATE                $(GOPRIVATE)"
	echo "  GOFLAGS                  $(GOFLAGS)"
	echo "  HTTP_PROXY               $(HTTP_PROXY)"
	echo "  HTTPS_PROXY              $(HTTPS_PROXY)"
ifneq (, $(GIT_CREDENTIALS))
	echo "  GIT_CREDENTIALS          [masked]"
else
	echo "  GIT_CREDENTIALS          "
endif

help: # @HELP print this message
help: variables
	echo "MAKE_TARGETS:"
	grep -E '^.*: *# *@HELP' $(MAKEFILE_LIST)    \
	    | sed -E 's_.*.mk:__g'                   \
	    | awk '                                  \
	        BEGIN {FS = ": *# *@HELP"};          \
	        { printf "  %-23s %s\n", $$1, $$2 }; \
	    '
