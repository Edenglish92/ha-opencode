ARG BUILD_FROM
# hadolint ignore=DL3006
FROM ${BUILD_FROM}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Le builder Home Assistant fournit BUILD_VERSION. On la fige dans un fichier
# plutot que dans une variable d'environnement : un ENV serait herite par le
# service puis par le shell des outils, comme l'etait OPENCODE_PASSWORD.
ARG BUILD_VERSION="inconnue"
RUN printf '%s\n' "${BUILD_VERSION}" > /app.version

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        git \
        jq \
        qrencode \
        tar \
    && rm -rf /var/lib/apt/lists/*

COPY config/assist-agent.json /etc/assist-agent.json
COPY run.sh /run.sh
RUN chmod +x /run.sh

CMD ["/run.sh"]
