FROM golang:1.25.0-bookworm AS go

FROM node:22-bullseye

COPY --from=go /usr/local/go /usr/local/go

ENV PATH="/usr/local/go/bin:${PATH}" \
    GOPATH=/claude-home/go \
    GOMODCACHE=/claude-home/go/pkg/mod \
    GOCACHE=/claude-home/.cache/go-build

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        build-essential \
        ca-certificates \
        curl \
        file \
        git \
        jq \
        make \
        openjdk-17-jdk-headless \
        openssh-client \
        procps \
        python3 \
        python3-pip \
        python3-venv \
        ripgrep \
        unzip \
        zip \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code@latest

WORKDIR /workspace

CMD ["claude"]
