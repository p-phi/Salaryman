FROM debian:bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash curl ca-certificates jq git build-essential cmake \
 && rm -rf /var/lib/apt/lists/*

# llama.cpp: build both the server and the CLI from a pinned tag.
ARG LLAMA_CPP_TAG=b12039
RUN git clone --depth 1 --branch "${LLAMA_CPP_TAG}" \
      https://github.com/ggml-org/llama.cpp /opt/llama.cpp \
 && cmake -S /opt/llama.cpp -B /opt/llama.cpp/build \
      -DBUILD_SHARED_LIBS=OFF -DLLAMA_CURL=ON -DCMAKE_BUILD_TYPE=Release \
 && cmake --build /opt/llama.cpp/build -j"$(nproc)" \
      --target llama-server llama-cli \
 && cp /opt/llama.cpp/build/bin/llama-server /usr/local/bin/ \
 && cp /opt/llama.cpp/build/bin/llama-cli    /usr/local/bin/ \
 && rm -rf /opt/llama.cpp

# salaryman, via the project's own installer.
ARG SALARYMAN_INSTALL_URL=https://raw.githubusercontent.com/p-phi/salaryman/main/install.sh
RUN curl -fsSL "${SALARYMAN_INSTALL_URL}" | bash -s -- --unattended
ENV PATH="/root/.local/bin:${PATH}"

# shunit2, vendored.
ARG SHUNIT2_VERSION=2.1.8
RUN curl -fsSL -o /opt/shunit2 \
      "https://raw.githubusercontent.com/kward/shunit2/v${SHUNIT2_VERSION}/shunit2" \
 && chmod +x /opt/shunit2

# The suite and the agents it needs.
COPY inside/ /opt/e2e/inside/
COPY agents/  /agents/

# The GGUF is mounted at /models at run time.
ENV SALARYMAN_MODEL_PATH=/models/model.gguf
ENV SHUNIT2=/opt/shunit2

WORKDIR /work
ENTRYPOINT ["bash", "/opt/e2e/inside/test_hostname.sh"]
