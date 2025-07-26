Verify Certificates

```
ls /opt/zextras/common/certbot/etc/letsencrypt/
```

All in One Cron Generate
==

```
wget https://raw.githubusercontent.com/server-tools/carbonio-letsencrypt/refs/heads/main/cert_cron.sh
chmod +x cert_cron.sh
```

Open Crontab:

```
crontab -e
```

add the following line

```
0 2 * * * /root/cert_cron.sh
```



Generate SSL
==

```
wget https://raw.githubusercontent.com/server-tools/carbonio-letsencrypt/refs/heads/main/run_certbot.sh
chmod +x run_certbot.sh
./run_certbot.sh user@example.com example.com
```
Deploy SSL
==
```
wget https://raw.githubusercontent.com/server-tools/carbonio-letsencrypt/refs/heads/main/deploy_cert.sh
chmod +x deploy_cert.sh
./deploy_cert.sh example.com
```
