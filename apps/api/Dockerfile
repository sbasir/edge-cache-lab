FROM golang:1.26-alpine AS build

WORKDIR /src

COPY go.mod ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /bin/server ./cmd/server

FROM alpine:3.23

RUN addgroup -S app && adduser -S app -G app
USER app

ENV PORT=3000
EXPOSE 3000

COPY --from=build /bin/server /bin/server

ENTRYPOINT ["/bin/server"]
