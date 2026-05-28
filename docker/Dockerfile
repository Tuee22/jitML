FROM ubuntu:24.04

ARG GHC_VERSION=9.14.1
ARG STYLE_GHC_VERSION=9.12.4
ARG CABAL_VERSION=3.16.1.0
ARG NODE_VERSION=22.16.0
ARG CUDA_TOOLKIT_PACKAGE=cuda-toolkit-12-8
ARG CUDNN_PACKAGE=libcudnn9-dev-cuda-12
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

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
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

RUN curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org \
    | BOOTSTRAP_HASKELL_NONINTERACTIVE=1 BOOTSTRAP_HASKELL_GHC_VERSION=${GHC_VERSION} BOOTSTRAP_HASKELL_CABAL_VERSION=${CABAL_VERSION} sh

RUN ghcup install ghc "${STYLE_GHC_VERSION}" \
    && mkdir -p "${JITML_STYLE_TOOLS_ROOT}/bin" \
    && printf 'jitml:local\n' > /opt/jitml-code-quality-domain \
    && cabal update \
    # Install a known-good happy first so the ghc-lib-parser build picks
    # it up via PATH rather than building its own which has hit version-
    # detection failures under Docker. Pin happy-1.20.1.1 (the canonical
    # version range for ghc-lib-parser 9.12.x).
    && ghcup run --ghc "${STYLE_GHC_VERSION}" -- cabal install \
        --ignore-project \
        --installdir "${JITML_STYLE_TOOLS_ROOT}/bin" \
        --install-method=copy \
        --jobs=1 \
        happy-1.20.1.1 \
    && export PATH="${JITML_STYLE_TOOLS_ROOT}/bin:${PATH}" \
    && ghcup run --ghc "${STYLE_GHC_VERSION}" -- cabal install \
        --ignore-project \
        --installdir "${JITML_STYLE_TOOLS_ROOT}/bin" \
        --install-method=copy \
        --jobs=1 \
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
    && curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/v1.32.2/bin/linux/${tool_arch}/kubectl" \
    && chmod 0755 /usr/local/bin/kubectl \
    && curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash \
    && curl -fsSL -o /usr/local/bin/kind "https://kind.sigs.k8s.io/dl/v0.27.0/kind-linux-${tool_arch}" \
    && chmod 0755 /usr/local/bin/kind \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /jitml

COPY . .

RUN cabal build -fcuda --jobs=2 --ghc-options="+RTS -M2G -RTS" exe:jitml exe:jitml-demo \
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
