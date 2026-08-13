FROM golang:1.22-alpine AS build
WORKDIR /src
COPY api-core/go.mod ./
RUN go mod download 2>/dev/null || true
COPY api-core/ .
RUN go mod tidy && CGO_ENABLED=0 go build -o /out/api-core ./cmd

FROM alpine:3.20
RUN apk add --no-cache ca-certificates iproute2 wireguard-tools iptables
WORKDIR /app
COPY --from=build /out/api-core ./api-core
COPY migrations ./migrations
# `releases` NÃO é copiado: o compose monta `./releases:/app/releases:ro`, e o
# mount mascarava a cópia no instante em que o container subia. A cópia
# produzia uma imagem de 17 GB e ~12 min de build para um diretório que nunca
# era lido. O diretório é criado vazio para que o binário encontre o caminho
# mesmo se alguém rodar a imagem sem o mount.
RUN mkdir -p /app/releases
EXPOSE 8080
ENTRYPOINT ["./api-core"]
