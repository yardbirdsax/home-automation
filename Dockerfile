FROM golang:1.24rc2 AS builder
WORKDIR /app
COPY go.* ./
RUN go mod download
COPY . .
ENV CGO_ENABLED=0
RUN go build -o ./dist/api ./cmd/api

FROM scratch
WORKDIR /app
COPY --from=builder ./app ./

EXPOSE 8080
CMD [ "./app" ]
