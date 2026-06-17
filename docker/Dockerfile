FROM ubuntu:24.04

ARG GHC_VERSION=9.12.4
ARG CABAL_VERSION=3.16.1.0
ARG NODE_VERSION=22.16.0
# jitML's JIT path needs the CUDA compiler (nvcc) and the dev libraries
# (cudart, cublas, nvrtc, …). It does NOT need the Nsight GUI profilers or
# docs that the `cuda-toolkit-12-8` metapackage drags in via
# `cuda-tools-12-8` — those balloon the image to ~21GB and the large
# `nsight-compute` .deb has downloaded corrupt (lzma) on constrained hosts,
# producing layer blobs that break `docker save` / `kind load`. Install the
# compiler + dev-library metapackages directly so Nsight is never fetched.
ARG CUDA_TOOLKIT_PACKAGE="cuda-compiler-12-8 cuda-libraries-dev-12-8 cuda-nvrtc-dev-12-8 cuda-nvml-dev-12-8"
ARG CUDNN_PACKAGE=libcudnn9-dev-cuda-12
ARG ALE_VERSION=v0.12.0
ARG ALE_COMMIT=94c24368664b8539c53857522e50652ddcc44b20
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV PATH=/root/.ghcup/bin:/root/.cabal/bin:/usr/local/cuda/bin:/usr/local/bin:$PATH
# Sprint 13.11 — at runtime the NVIDIA Container Toolkit injects the real
# host driver libraries under /usr/lib/x86_64-linux-gnu/. The CUDA-shipped
# `libcuda.so` under `lib64/stubs/` is a link-time stub that returns
# `cudaErrorNoDevice` at runtime; including its directory in LD_LIBRARY_PATH
# shadows the injected real driver and breaks `nvidia-smi`/CUDA inside the
# compose container. Keep stubs available for nvcc at link time via the
# explicit `-L` in the JIT compile command — not on LD_LIBRARY_PATH.
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
ENV JITML_STYLE_TOOLS_ROOT=/opt/jitml-style-tools
ENV CABAL_CONFIG=/root/.cabal/config

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        cmake \
        curl \
        docker.io \
        g++ \
        gcc \
        git \
        gnupg \
        libffi-dev \
        libdnnl-dev \
        libgmp-dev \
        libncurses-dev \
        libnuma-dev \
        llvm \
        make \
        nodejs \
        npm \
        python3 \
        python3-pip \
        pkg-config \
        unzip \
        wget \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Build Arcade Learning Environment from a pinned upstream source commit. Ubuntu
# 24.04 does not provide `libale-dev`, and commercial ROM bytes are never baked
# into the image; callers provide an explicit uncommitted ROM path at runtime.
RUN git clone --depth 1 --branch "${ALE_VERSION}" \
        https://github.com/Farama-Foundation/Arcade-Learning-Environment.git \
        /tmp/arcade-learning-environment \
    && cd /tmp/arcade-learning-environment \
    && test "$(git rev-parse HEAD)" = "${ALE_COMMIT}" \
    && cmake -S . -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_CPP_LIB=ON \
        -DBUILD_PYTHON_LIB=OFF \
        -DBUILD_VECTOR_LIB=OFF \
        -DBUILD_VECTOR_XLA_LIB=OFF \
        -DBUILD_WASM_LIB=OFF \
        -DSDL_SUPPORT=OFF \
    && cmake --build build --target install --parallel 2 \
    && ldconfig \
    && rm -rf /tmp/arcade-learning-environment

# Install the CUDA 12.8 toolkit + matching cuDNN 9 dev headers so the
# Haskell-rendered `kernel.cu` from `JitML.Codegen.Cuda` can compile and link
# against `-lcudart -lcublas -lcudnn`. Source-level scaffolding for cuBLAS GEMM
# / cuDNN convolution becomes real at compile time once these headers and
# stubs are present; the runtime driver still needs the host GPU at execution
# time (wire that through compose `deploy.resources.devices`).
RUN case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
        amd64) cuda_arch=x86_64 ;; \
        arm64 | aarch64) cuda_arch=sbsa ;; \
        *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
      esac \
    && wget -qO /tmp/cuda-keyring.deb \
        "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/${cuda_arch}/cuda-keyring_1.1-1_all.deb" \
    && dpkg -i /tmp/cuda-keyring.deb \
    && rm -f /tmp/cuda-keyring.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ${CUDA_TOOLKIT_PACKAGE} \
        ${CUDNN_PACKAGE} \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/local/cuda-12.8 /usr/local/cuda \
    # Sprint 13.11 — only the runtime libs (cudart, cublas, cudnn) belong on
    # the ldconfig cache; the stubs directory contains a link-time-only
    # `libcuda.so` that conflicts with the NVIDIA Container Toolkit's runtime
    # injection. nvcc continues to resolve the link-time stub via the
    # explicit `-L/usr/local/cuda/lib64/stubs` we pass during JIT compile.
    && printf '/usr/local/cuda/lib64\n' > /etc/ld.so.conf.d/cuda.conf \
    && ldconfig

# Use the standard secure Hackage endpoint directly. The hackage-content CDN
# can serve root metadata while returning transient 503s for snapshot metadata,
# which makes the bootstrap-owned legacy Docker build fail during `cabal update`.
RUN mkdir -p /root/.cabal \
    && printf 'repository hackage.haskell.org\n  url: https://hackage.haskell.org/\n' > /root/.cabal/config

RUN curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org \
    | BOOTSTRAP_HASKELL_NONINTERACTIVE=1 BOOTSTRAP_HASKELL_GHC_VERSION=${GHC_VERSION} BOOTSTRAP_HASKELL_CABAL_VERSION=${CABAL_VERSION} sh

RUN mkdir -p "${JITML_STYLE_TOOLS_ROOT}/bin" \
    && printf 'jitml:local\n' > /opt/jitml-code-quality-domain \
    && cabal update \
    # Install a known-good happy first so the ghc-lib-parser build picks
    # it up via PATH rather than building its own which has hit version-
    # detection failures under Docker. Pin happy-1.20.1.1 (the canonical
    # version range for ghc-lib-parser 9.12.x).
    && ghcup run --ghc "${GHC_VERSION}" -- cabal install \
        --ignore-project \
        --installdir "${JITML_STYLE_TOOLS_ROOT}/bin" \
        --install-method=copy \
        --jobs=1 \
        --ghc-options="+RTS -M2G -RTS" \
        happy-1.20.1.1 \
    && export PATH="${JITML_STYLE_TOOLS_ROOT}/bin:${PATH}" \
    && ghcup run --ghc "${GHC_VERSION}" -- cabal install \
        --ignore-project \
        --installdir "${JITML_STYLE_TOOLS_ROOT}/bin" \
        --install-method=copy \
        --jobs=1 \
        --ghc-options="+RTS -M2G -RTS" \
        --constraint="happy ==1.20.1.1" \
        fourmolu-0.19.0.1 \
        hlint-3.10 \
    && chmod 0755 "${JITML_STYLE_TOOLS_ROOT}/bin/fourmolu" "${JITML_STYLE_TOOLS_ROOT}/bin/hlint"

RUN case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
        amd64) tool_arch=amd64; node_arch=x64 ;; \
        arm64 | aarch64) tool_arch=arm64; node_arch=arm64 ;; \
        *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
      esac \
    && apt-get update \
    && apt-get install -y --no-install-recommends xz-utils \
    && curl -fsSL -o /tmp/node.tar.xz "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${node_arch}.tar.xz" \
    && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 \
    && rm -f /tmp/node.tar.xz \
    && npm install -g purescript spago purs-tidy \
    && curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/v1.34.0/bin/linux/${tool_arch}/kubectl" \
    && chmod 0755 /usr/local/bin/kubectl \
    && curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash \
    && curl -fsSL -o /usr/local/bin/kind "https://kind.sigs.k8s.io/dl/v0.27.0/kind-linux-${tool_arch}" \
    && chmod 0755 /usr/local/bin/kind \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /jitml

COPY . .

# Bound cabal's build parallelism for every build in this layer — including
# the `cabal build all --ghc-options=-Werror` warning-clean pass that
# `jitml check-code` runs, which has no --jobs flag of its own and otherwise
# defaults to one GHC per core. On a 16-core / 15GiB host that fans out to 16
# concurrent GHC processes and OOM-SIGSEGVs the compile; `jobs: 1` keeps the
# warning-clean build serial and within memory. The explicit `--jobs=2` on
# the binary build below still overrides this for the (heap-capped) exe build.
RUN printf 'jobs: 1\n' >> /root/.cabal/config \
    && cabal build -fcuda --jobs=1 --ghc-options="+RTS -M2G -RTS" exe:jitml exe:jitml-demo \
    && cp "$(cabal list-bin -fcuda exe:jitml)" /usr/local/bin/jitml \
    && cp "$(cabal list-bin -fcuda exe:jitml-demo)" /usr/local/bin/jitml-demo \
    && chmod 0755 /usr/local/bin/jitml /usr/local/bin/jitml-demo \
    && jitml check-code

# Bake the compiled PureScript bundle into the image. `spago build
# --output dist` emits per-module CommonJS CoreFn artifacts under
# `web/dist/<Module>/index.js`; a browser cannot resolve those
# `require` calls, so we additionally bundle the `Main` entry into a
# self-contained IIFE at `web/dist/Main/bundle.js` with esbuild. The
# demo container (no bind mount in Kind) serves that bundle from
# `JitML.Web.Server.loadBundleEntry`, switching the demo `/` route from
# the placeholder shell to a browser-loadable Halogen entry point that
# mounts the panel selected by `location.hash` (Sprint 13.13).
RUN cd /jitml/web \
    && spago build --output dist \
    && npx --yes esbuild dist/Main/index.js \
        --bundle \
        --format=iife \
        --global-name=jitmlDemo \
        --outfile=dist/Main/bundle.js \
    && printf 'jitmlDemo.main();\n' >> dist/Main/bundle.js

CMD ["jitml", "--help"]
