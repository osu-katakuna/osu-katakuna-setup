#!/bin/bash
DATABASE_PASS="katakuna"
DATABASE_DB="katakuna"
USERNAME_DB="katakuna"
PASSWORD_DB=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
VERSION="ALPHA-0.1"

printf "osu!katakuna setup\nversion $VERSION\n"

if [[ $EUID -ne 0 ]]; then
   printf "[X] osu!katakuna cannot be installed! This setup must be run as root! Exiting...\n"
   exit 1
fi

printf "[STAGE 1] System configuration.\n"
printf "\t=> Updating repositories...\n"
apt-get -qq update
printf "\t=> Installing dependencies...\n"
apt-get -qq install expect openssl apache2 mysql-server php libapache2-mod-php php-mysql git wget dirmngr apt-transport-https lsb-release ca-certificates gcc g++ make composer php-dev libmcrypt-dev php-pear -y
printf "\n" | pecl install mcrypt-1.0.1
echo "extension=mcrypt.so" >> /etc/php/*/cli/php.ini
echo "extension=mcrypt.so" >> /etc/php/*/apache2/php.ini
printf "\t=> Installing nodejs...\n"
curl -sL https://deb.nodesource.com/setup_10.x | sudo bash > /dev/null 2>&1
apt-get -qq install nodejs -y

printf "\t=> Configurating ufw...\n"
ufw allow in "Apache Full" > /dev/null 2>&1
printf "\t=> Configurating mysql...\t"
expect -f - > /dev/null 2>&1 <<-EOF
  log_user 0
  set timeout 10
  spawn mysql_secure_installation
  expect "Press y|Y for Yes, any other key for No:"
  send -- "n\r"
  expect "New password:"
  send -- "${DATABASE_PASS}\r"
  expect "Re-enter new password:"
  send -- "${DATABASE_PASS}\r"
  expect "Remove anonymous users?"
  send -- "y\r"
  expect "Disallow root login remotely?"
  send -- "y\r"
  expect "Remove test database and access to it?"
  send -- "y\r"
  expect "Reload privilege tables now?"
  send -- "y\r"
  expect eof
EOF
printf "[OK]\n"

printf "\t=> Updating mysql configuration...\t"
mysql -uroot -p"$DATABASE_PASS" -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$DATABASE_PASS'" > /dev/null 2>&1
mysql -uroot -p"$DATABASE_PASS" -e "CREATE DATABASE $DATABASE_DB" > /dev/null 2>&1
mysql -uroot -p"$DATABASE_PASS" -e "CREATE USER '$USERNAME_DB'@'localhost' IDENTIFIED BY '$PASSWORD_DB'" > /dev/null 2>&1
mysql -uroot -p"$DATABASE_PASS" -e "GRANT ALL PRIVILEGES ON '$DATABASE_DB'.* TO '$USERNAME_DB'@'localhost'" > /dev/null 2>&1
mysql -uroot -p"$DATABASE_PASS" -e "FLUSH PRIVILEGES" > /dev/null 2>&1
printf "[OK]\n"

printf "[STAGE 2] osu!katakuna setup\n"

printf "\t=> Configurating apache2...\n"
mv ./avatar-server.conf /etc/apache2/sites-available/avatar-server.conf > /dev/null 2>&1
mv ./communication-server.conf /etc/apache2/sites-available/communication-server.conf > /dev/null 2>&1
mv ./main-website.conf /etc/apache2/sites-available/main-website.conf > /dev/null 2>&1
a2enmod ssl > /dev/null 2>&1
a2enmod headers > /dev/null 2>&1
a2enmod proxy > /dev/null 2>&1
a2enmod proxy_http > /dev/null 2>&1
a2enmod rewrite > /dev/null 2>&1
a2ensite avatar-server > /dev/null 2>&1
a2ensite communication-server > /dev/null 2>&1
a2ensite main-website > /dev/null 2>&1

printf "\t=> Preparing to install osu!katakuna...\t"
mkdir /katakuna > /dev/null 2>&1
mkdir /katakuna/web > /dev/null 2>&1
mkdir /katakuna/certs > /dev/null 2>&1
mkdir /katakuna/server > /dev/null 2>&1
chown www-data:www-data /katakuna/web -Rf
chown www-data:www-data /katakuna/web/* -Rf
printf "[DONE]\n"

printf "\t=> Downloading latest version of osu!katakuna...\t"
git clone https://github.com/osu-katakuna/osu-katakuna-web.git /katakuna/web > /dev/null 2>&1
git clone https://github.com/osu-katakuna/osu-katakuna.git /katakuna/server > /dev/null 2>&1
mkdir /katakuna/web/database/factories > /dev/null 2>&1
printf "[OK]\n"

printf "\t=> Configurating osu!katakuna...\t"
wget -O /katakuna/web/.env https://raw.githubusercontent.com/laravel/laravel/master/.env.example > /dev/null 2>&1
cd /katakuna/web && composer install > /dev/null 2>&1
cd /katakuna/web && php artisan key:generate > /dev/null 2>&1
sed -i "/^APP_NAME=/s/=.*/=Katakuna/" /katakuna/web/.env
sed -i "/^DB_DATABASE=/s/=.*/=${DATABASE_DB}/" /katakuna/web/.env
sed -i "/^DB_USERNAME=/s/=.*/=${USERNAME_DB}/" /katakuna/web/.env
sed -i "/^DB_PASSWORD=/s/=.*/=${PASSWORD_DB}/" /katakuna/web/.env
cd /katakuna/web && php artisan migrate:fresh > /dev/null 2>&1
cd /katakuna/server && sudo npm install > /dev/null 2>&1
cat <<-EOF > /katakuna/server/global/config.json
{
  "database": {
    "host": "localhost",
    "username": "${USERNAME_DB}",
    "password": "${PASSWORD_DB}",
    "database": "${DATABASE_DB}"
  },
  "ports": {
    "web": 8080,
    "avatar": 8081
  },
  "certs": {
    "key": "/katakuna/certs/key.pem",
    "certificate": "/katakuna/certs/cacert.pem"
  },
  "ipc": true
}
EOF
cat <<-EOF > /lib/systemd/system/katakuna.service
[Unit]
Description=osu!katakuna server
Documentation=https://github.com/osu-katakuna/osu-katakuna
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/screen -DmS katakuna node /katakuna/server/main
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable katakuna
printf "[OK]\n"

printf "\t=> Generating certificates... Please be patient.\t"
openssl req -x509 -batch -passout pass:katakuna -newkey rsa:2048 -keyout /katakuna/certs/key_private.pem -out /katakuna/certs/cacert.pem -days 8760 -subj "/C=RO/ST=Bucharest/L=*.ppy.sh/O=osu!katakuna/OU=*.ppy.sh/CN=*.ppy.sh" > /dev/null 2>&1
openssl x509 -inform PEM -in /katakuna/certs/cacert.pem -outform DER -out /katakuna/certs/client.cer > /dev/null 2>&1
openssl rsa -in /katakuna/certs/key_private.pem -out /katakuna/certs/key.pem -passin pass:katakuna > /dev/null 2>&1
printf "[DONE]\n"

printf "\t=> Performing last steps...\t"
systemctl restart apache2
systemctl start katakuna
printf "[OK]\n"

printf "osu!katakuna installed successfully!\n"
printf "While creating your switcher, PLEASE USE the certificate found in /katakuna/certs/client.cer\n"
