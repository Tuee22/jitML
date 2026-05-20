FROM ubuntu:24.04

ARG GHC_VERSION=9.14.1
ARG STYLE_GHC_VERSION=9.12.4
ARG CABAL_VERSION=3.16.1.0
ARG NODE_VERSION=22.16.0
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV PATH=/root/.ghcup/bin:/root/.cabal/bin:/usr/local/bin:$PATH
ENV JITML_STYLE_TOOLS_ROOT=/opt/jitml-style-tools
ENV JITML_STYLE_TOOLS_BIN=/opt/jitml-style-tools/bin

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
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org \
    | BOOTSTRAP_HASKELL_NONINTERACTIVE=1 BOOTSTRAP_HASKELL_GHC_VERSION=${GHC_VERSION} BOOTSTRAP_HASKELL_CABAL_VERSION=${CABAL_VERSION} sh

RUN ghcup install ghc "${STYLE_GHC_VERSION}" \
    && mkdir -p "${JITML_STYLE_TOOLS_BIN}" \
    && cabal update \
    && ghcup run --ghc "${STYLE_GHC_VERSION}" -- cabal install \
        --ignore-project \
        --installdir "${JITML_STYLE_TOOLS_BIN}" \
        --install-method=copy \
        fourmolu-0.19.0.1 \
        hlint-3.10 \
    && chmod 0755 "${JITML_STYLE_TOOLS_BIN}/fourmolu" "${JITML_STYLE_TOOLS_BIN}/hlint"

RUN case "${TARGETARCH:-amd64}" in \
        amd64) tool_arch=amd64; node_arch=x64 ;; \
        arm64) tool_arch=arm64; node_arch=arm64 ;; \
        *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
      esac \
    && apt-get update \
    && apt-get install -y --no-install-recommends xz-utils \
    && curl -fsSL -o /tmp/node.tar.xz "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${node_arch}.tar.xz" \
    && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 \
    && rm -f /tmp/node.tar.xz \
    && npm install -g purescript spago \
    && curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/v1.32.2/bin/linux/${tool_arch}/kubectl" \
    && chmod 0755 /usr/local/bin/kubectl \
    && curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash \
    && curl -fsSL -o /usr/local/bin/kind "https://kind.sigs.k8s.io/dl/v0.27.0/kind-linux-${tool_arch}" \
    && chmod 0755 /usr/local/bin/kind \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /jitml

COPY . .

RUN cabal build exe:jitml exe:jitml-demo \
    && cp "$(cabal list-bin exe:jitml)" /usr/local/bin/jitml \
    && cp "$(cabal list-bin exe:jitml-demo)" /usr/local/bin/jitml-demo \
    && chmod 0755 /usr/local/bin/jitml /usr/local/bin/jitml-demo \
    && jitml check-code

CMD ["jitml", "--help"]
