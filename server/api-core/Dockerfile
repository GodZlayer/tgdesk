FROM golang:1.22-alpine AS build
WORKDIR /src
COPY api-core/go.mod ./
RUN go mod download 2>/dev/null || true
COPY api-core/ .
RUN go mod tidy && CGO_ENABLED=0 go build -o /out/api-core ./cmd

FROM alpine:3.20
RUN apk add --no-cache ca-certificates iproute2 wireguard-tools
WORKDIR /app
COPY --from=build /out/api-core ./api-core
COPY migrations ./migrations
EXPOSE 8080
ENTRYPOINT ["./api-core"]
