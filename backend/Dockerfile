FROM golang:1.26-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /server ./cmd/server

FROM alpine:3.22

# `upgrade` avant `add` : l'etiquette alpine:3.22 est figee a la date de sa
# publication, alors que les correctifs de securite de ses paquets (libssl,
# libcrypto) sortent en continu. Sans cette ligne, l'image embarque les
# versions du jour de la release d'alpine, pas les versions corrigees, et le
# scan Trivy de la CI echoue dessus.
RUN apk --no-cache upgrade && apk --no-cache add ca-certificates tzdata

# Compte non privilegie : une execution de code arbitraire dans le serveur ne
# doit pas donner root dans le conteneur.
RUN addgroup -g 10001 -S streampulse \
 && adduser -u 10001 -S -G streampulse -H -s /sbin/nologin streampulse

WORKDIR /app
COPY --from=builder /server /app/server
COPY config.yaml /app/config.yaml

# filestore.NewFileStore ecrit dans ./uploads, relatif au WORKDIR. Le
# repertoire est cree ici et attribue au compte de service : cree au premier
# upload il appartiendrait a root, et l'ecriture echouerait.
RUN mkdir -p /app/uploads && chown -R streampulse:streampulse /app

USER streampulse:streampulse

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://localhost:8080/health || exit 1
ENTRYPOINT ["/app/server"]
