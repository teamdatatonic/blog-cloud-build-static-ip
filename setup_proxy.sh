echo "Installing latest Go toolchain"
LATEST_GO_VERSION="$(curl --silent https://go.dev/VERSION?m=text)"
curl -OJ -L --progress-bar https://golang.org/dl/${LATEST_GO_VERSION}.linux-amd64.tar.gz
rm -rf /usr/local/go && tar -C /usr/local -xzf ${LATEST_GO_VERSION}.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin
echo "Done."

cat <<END >/home/install.sh
export PATH=$PATH:/usr/local/go/bin

echo "Checking for old executable... (/usr/local/bin/proxy-srv)"
[ -f /usr/local/bin/proxy-srv ] && rm -f /usr/local/bin/proxy-srv
echo "Done."


echo "Building from source"
cat <<EOF > ./main.go
package main


import (
  "flag"
  "fmt"
  "log"
  "net/http"
  "github.com/elazarl/goproxy"
)


func main() {
  verbose := flag.Bool("v", false, "log every proxy request to stdout")
  port := flag.String("port", "9231", "proxy listen port")
  flag.Parse()


  proxy := goproxy.NewProxyHttpServer()
  proxy.Verbose = *verbose


  addr := fmt.Sprintf(":%s", *port)
  log.Printf("Proxy is listening on port %s\n", *port)
  err := http.ListenAndServe(addr, proxy)
  if err != nil {
     log.Fatalf("error while starting the proxy on port %s: %s\n", *port, err.Error())
  }
}
EOF
cat <<EOF > go.mod
module github.com/teamdatatonic/go-proxy-vm


go 1.19


require github.com/elazarl/goproxy v0.0.0-20221015165544-a0805db90819
EOF
go mod tidy
GOOS=linux GOARCH=amd64 go build -o ./proxy-srv
mv ./proxy-srv /usr/local/bin/proxy-srv
echo "Done."


echo "Stoping old service if exists..."
if systemctl --all --type service | grep -q "proxy-srv";then
  systemctl stop proxy-srv.service
fi
echo "Done."


echo "Creating new service file... (/lib/systemd/system/proxy-srv.service)"
cat <<EOF > /lib/systemd/system/proxy-srv.service
[Unit]
Description=NAME Proxy Server Service
ConditionPathExists=/usr/local/bin
After=network.target
[Service]
Type=simple
Restart=always
ExecStart=/usr/local/bin/proxy-srv -v -port=9231
[Install]
WantedBy=multi-user.target
EOF
echo "Done."


echo "Starting and enabling proxy-srv.service"
systemctl daemon-reload
systemctl start proxy-srv.service
systemctl enable proxy-srv.service
echo "Done."
END
cd /home
sudo sh install.sh
