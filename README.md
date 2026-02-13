# Edge Cache Lab

## Local dev

```sh
make api-init
make api-test
make api-run
curl http://localhost:3000/
```

## Local Docker dev

```sh
make docker-up
make docker-logs

curl -i http://localhost:3000/

make docker-down
```
