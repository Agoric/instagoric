FROM ghcr.io/agoric/agoric-sdk:latest

ENV PATH="/usr/src/agoric-sdk/bin:${PATH}"

WORKDIR /usr/instagoric-server
COPY . .
RUN yarn install
EXPOSE 8001 8002 8003

