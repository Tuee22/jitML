FROM ubuntu:24.04

ARG GHC_VERSION=9.14.1
ARG CABAL_VERSION=3.16.1.0

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH=/root/.ghcup/bin:/root/.cabal/bin:/usr/local/bin:$PATH

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        docker.io \
        g++ \
        gcc \
        git \
        gnupg \
        libnuma-dev \
        llvm \
        make \
        nodejs \
        npm \
        python3 \
        python3-pip \
        unzip \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org \
    | BOOTSTRAP_HASKELL_NONINTERACTIVE=1 BOOTSTRAP_HASKELL_GHC_VERSION=${GHC_VERSION} BOOTSTRAP_HASKELL_CABAL_VERSION=${CABAL_VERSION} sh

RUN npm install -g purescript spago \
    && curl -fsSL -o /usr/local/bin/kubectl https://dl.k8s.io/release/v1.32.2/bin/linux/amd64/kubectl \
    && chmod 0755 /usr/local/bin/kubectl \
    && curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash \
    && curl -fsSL -o /usr/local/bin/kind https://kind.sigs.k8s.io/dl/v0.27.0/kind-linux-amd64 \
    && chmod 0755 /usr/local/bin/kind

WORKDIR /jitml

CMD ["jitml", "--help"]
