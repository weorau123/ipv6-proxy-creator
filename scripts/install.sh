#!/bin/sh

random() {
  tr </dev/urandom -dc A-Za-z0-9 | head -c5
  echo
}

array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
gen64() {
  ip64() {
    echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
  }
  echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

install_3proxy() {
  echo "Installing 3proxy"
  URL="https://github.com/z3APA3A/3proxy/archive/3proxy-0.8.6.tar.gz"
  wget -qO- $URL | bsdtar -xvf-
  cd 3proxy-3proxy-0.8.6
  make -f Makefile.Linux
  mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
  cp src/3proxy /usr/local/etc/3proxy/bin/
  cp ./scripts/rc.d/proxy.sh /etc/init.d/3proxy
  chmod +x /etc/init.d/3proxy
  chkconfig 3proxy on
  cd $WORKDIR
}

gen_3proxy() {
  cat <<EOF
daemon
maxconn 1000
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
flush
auth strong

users $(awk -F "/" 'BEGIN{ORS="";} {print $1 ":CL:" $2 " "}' ${WORKDATA})

$(awk -F "/" '{print "auth strong\n" \
"allow " $1 "\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\n" \
"flush\n"}' ${WORKDATA})
EOF
}

gen_proxy_file_for_user() {
  cat >proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' ${WORKDATA})
EOF
}

install_jq() {
  wget -O jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
  chmod +x ./jq
  cp jq /usr/bin
}

gen_data() {
  seq $FIRST_PORT $LAST_PORT | while read port; do
    echo "usr$(random)/pass$(random)/$IP4/$port/$(gen64 $IP6)"
  done
}

gen_iptables() {
  cat <<EOF
    $(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 "  -m state --state NEW -j ACCEPT"}' ${WORKDATA})
EOF
}

gen_ifconfig() {
  cat <<EOF
$(awk -F "/" '{print "ifconfig eth0 inet6 add " $5 "/64"}' ${WORKDATA})
EOF
}

# Cài đặt các phần mềm cần thiết
echo "Installing necessary applications"
yum -y install gcc net-tools bsdtar zip wget curl >/dev/null

# Cài đặt 3proxy
install_3proxy

# Thiết lập thư mục làm việc
WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"
mkdir -p $WORKDIR && cd $_

# Lấy IP nội bộ và IP công cộng (IPv6 và IPv4)
IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "Internal IP = ${IP4}. External IPv6 prefix = ${IP6}"

# Nhập số lượng proxy muốn tạo
echo "How many proxies do you want to create? Example: 500"
read COUNT

FIRST_PORT=10000
LAST_PORT=$(($FIRST_PORT + $COUNT))

# Tạo dữ liệu cho các proxy
gen_data >$WORKDIR/data.txt
gen_iptables >$WORKDIR/boot_iptables.sh
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
chmod +x boot_*.sh /etc/rc.local

# Tạo file cấu hình 3proxy
gen_3proxy >/usr/local/etc/3proxy/3proxy.cfg

# Thêm script vào /etc/rc.local để tự động chạy khi khởi động
cat >>/etc/rc.local <<EOF
bash ${WORKDIR}/boot_iptables.sh
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -n 10048
service 3proxy start
EOF

# Chạy script khởi động
bash /etc/rc.local

# Tạo file proxy.txt với thông tin proxy cho người dùng
gen_proxy_file_for_user

echo "Proxy configuration and file generation completed."
