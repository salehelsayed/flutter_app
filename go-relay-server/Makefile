.PHONY: build run clean tidy

build:
	go build -o relay-server .

run: build
	./relay-server

tidy:
	go mod tidy

clean:
	rm -f relay-server
