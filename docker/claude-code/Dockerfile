FROM node:22-bullseye

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
