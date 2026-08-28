FROM golang:1.26-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /server ./cmd/server

FROM alpine:3.22
# `upgrade` avant `add` : l'etiquette alpine:3.22 est figee a la date de
# sa publication, alors que les correctifs de securite de ses paquets
# (libssl, libcrypto) sortent en continu. Sans cette ligne, l'image
# embarque les versions du jour de la release d'alpine, pas les versions
# corrigees. Le scan Trivy de la CI echouerait dessus.
RUN apk --no-cache upgrade && apk --no-cache add ca-certificates tzdata
COPY --from=builder /server /server
COPY config.yaml /config.yaml
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://localhost:8080/health || exit 1
ENTRYPOINT ["/server"]
