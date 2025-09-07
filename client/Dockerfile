FROM golang:1.24-alpine AS builder

WORKDIR /app
COPY client/go.mod client/go.sum ./
RUN go mod download

# Install protoc and protoc-gen-go
RUN apk add --no-cache protobuf-dev
RUN go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
RUN go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest

# Copy proto files and generate Go code
COPY ./proto ./proto
RUN ls -ltr ./proto
RUN protoc --go_out=. --go_opt=paths=source_relative \
    --go-grpc_out=. --go-grpc_opt=paths=source_relative \
    ./proto/ping.proto

COPY client .
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o client .

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=builder /app/client .
CMD ["./client"]