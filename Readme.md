```
Сценарии iptables

Цель: Студент получил навыки работы с centralServer, inetRouter.
1) реализовать knocking port
- centralRouter может попасть на ssh inetrRouter через knock скрипт
пример в материалах
2) добавить inetRouter2, который виден(маршрутизируется (host-only тип сети для виртуалки)) с хоста или форвардится порт через локалхост
3) запустить nginx на centralServer
4) пробросить 80й порт на inetRouter2 8080
5) дефолт в инет оставить через inetRouter

* реализовать проход на 80й порт без маскарадинга
Критерии оценки: 5 - все сделано 
```

### Выполнение ДЗ

1. реализовать knocking port - centralRouter может попасть на ssh inetRouter через knock скрипт

Реализовать данную опцию можно несколькими способами:

- Импорт правил в таблицы iptables. У данного способа есть свои преимущества в виде независимости от других программ
Данный конфиг говорит на следующее - если был перебор портов с последовательностью портов 2222 3333 4444, то открыть порт 22 на 30 секунд. Уже установленные SSH соединения не будут отброшены, так как есть специальная таблица уже установленных соединений conntrack, и если там будет соединение то его файервол сбрасывать не будет 
```
cat <<EOT | iptables-restore
*filter
:INPUT DROP [0:0]
:FORWARD ACCEPT [12816:43815755]
:OUTPUT ACCEPT [106:11577]
:SSH-INPUT - [0:0]
:SSH-INPUTTWO - [0:0]
:TRAFFIC - [0:0]
-A INPUT -j TRAFFIC
-A SSH-INPUT -m recent --set --name SSH1 --mask 255.255.255.255 --rsource -j DROP
-A SSH-INPUTTWO -m recent --set --name SSH2 --mask 255.255.255.255 --rsource -j DROP
-A TRAFFIC -p icmp -m icmp --icmp-type any -j ACCEPT
-A TRAFFIC -m state --state RELATED,ESTABLISHED -j ACCEPT
-A TRAFFIC -p tcp -m state --state NEW -m tcp --dport 22 -m recent --rcheck --seconds 30 --name SSH2 --mask 255.255.255.255 --rsource -j ACCEPT
-A TRAFFIC -p tcp -m state --state NEW -m tcp -m recent --remove --name SSH2 --mask 255.255.255.255 --rsource -j DROP
-A TRAFFIC -p tcp -m state --state NEW -m tcp --dport 4444 -m recent --rcheck --name SSH1 --mask 255.255.255.255 --rsource -j SSH-INPUTTWO
-A TRAFFIC -p tcp -m state --state NEW -m tcp -m recent --remove --name SSH1 --mask 255.255.255.255 --rsource -j DROP
-A TRAFFIC -p tcp -m state --state NEW -m tcp --dport 3333 -m recent --rcheck --name SSH0 --mask 255.255.255.255 --rsource -j SSH-INPUT
-A TRAFFIC -p tcp -m state --state NEW -m tcp -m recent --remove --name SSH0 --mask 255.255.255.255 --rsource -j DROP
-A TRAFFIC -p tcp -m state --state NEW -m tcp --dport 2222 -m recent --set --name SSH0 --mask 255.255.255.255 --rsource -j DROP
-A TRAFFIC -j DROP
COMMIT
EOT
```
- Использование таких программ как knock 
Для начала надо прописать правила в iptables и сохранить их:
```sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT; sudo iptables -A INPUT -p tcp --dport 22 -j REJECT; sudo service iptables save```

Затем привести файлы конфигурации к следующему виду:

```/etc/knockd.conf```:

```
options]
	UseSyslog

[opencloseSSH]
	sequence      = 2222:tcp,3333:tcp,4444:tcp
        seq_timeout   = 15
        tcpflags      = syn
        start_command = /sbin/iptables -I INPUT 1 -s %IP% -p tcp --dport 22 -j ACCEPT
        cmd_timeout   = 30
        stop_command  = /sbin/iptables -D INPUT -s %IP% -p tcp --dport ssh -j ACCEPT
```

```/etc/sysconfig/knockd```:

```
OPTIONS="-i eth1"
```

Также необходимо что лучше переделать файл запуска с версии SysV к unit файлу, или в крайнем случае добавить на 23 строку файла ```/etc/init.d/knock``` директиву ```sleep 30``` и далее сделать systemctl daemon-reload. 

Мы своего добились, теперь можно проверить настройку knocking port. Необходимо зайти на centralRouter командой ```vagrant ssh centralRouter``` и выполнить:
```
 for x in 2222 3333 4444; do sudo nmap -Pn --host_timeout 100 --max-retries 0 -p $x 192.168.255.1; done
```
Здесь программа nmap перебирает в цикле порты по определенной последовательности (в продакшен среде не рекомендуется использовать такие простые номера портов и их должно быть больше)

Также можно установить на centalRouter программу knock и выполнить сдедующую команду ```knock 192.168.4.24 2222 3333 4444 -d 500```, где d это delay 500 мс между портами.

Дополнительная информация по knock: 

https://www.howtogeek.com/442733/how-to-use-port-knocking-on-linux-and-why-you-shouldnt/

https://putty.org.ru/articles/port-knocking.html


2. Добавить inetRouter2, который виден(маршрутизируется (host-only тип сети для виртуалки)) с хоста или форвардится порт через локалхост

Добавлен в вагрант директивой ```box.vm.network "forwarded_port", guest: 8080, host: 1234, host_ip: "127.0.0.1", id: "nginx"``` (смотрите вагрант файл)

3. запустить nginx на centralServer 

Добавлено директивами: ```sudo yum install -y epel-release; sudo yum install -y nginx; sudo systemctl enable nginx; sudo systemctl start nginx``` (смотрите вагрант файл)

4. Пробросить 80й порт на inetRouter2 8080

В данном случае когда мы переходим по адресу 127.0.0.1 порт 1234 то мы попадаем на порт 8080 гостевой машины inetRouter2.
Затем правилами iptables мы управляем пакетами, которые пришли на порт 8080 интерфейса eth0 и отправляем их по адресу 192.168.0.2 порт 80. Исходя из правил маршрутизации компьютер знает куда отправлять дальше данные пакеты, и он их отправляет на 192.168.255.3 (centralRouter), далее они попадают на веб-сервер 192.168.0.2 на порт 80 после чего возвращаются отправителю обратно в той же последовательности. (смотрите схему)

Правила iptables для inetRouter2:
```
sudo iptables -t nat -A PREROUTING -i eth0 -p tcp -m tcp --dport 8080 -j DNAT --to-destination 192.168.0.2:80
sudo iptables -t nat -A POSTROUTING --destination 192.168.0.2/32 -j SNAT --to-source 192.168.255.2
```

Стоит учесть при работе с iptables, что маскарадинг работает медленнее чем SNAT (обратитесь к документации).


Дополнительная информация:

https://www.karlrupp.net/en/computer/nat_tutorial

http://www.k-max.name/linux/iptables-v-primerax/

http://www.k-max.name/linux/netfilter-iptables-v-linux/

http://jensd.be/343/linux/forward-a-tcp-port-to-another-ip-or-port-using-nat-with-iptables

http://linux-ip.net/html/nat-dnat.html

https://gist.github.com/tomasinouk/eec152019311b09905cd



5. Все гостевые машины по умолчанию ходят в интернет через 192.168.255.1 (inetRouter), для этого сделаны настройки (на примере centralServer):
```
echo "DEFROUTE=no" >> /etc/sysconfig/network-scripts/ifcfg-eth0 
echo "GATEWAY=192.168.0.1" >> /etc/sysconfig/network-scripts/ifcfg-eth1
```
Т.е. мы выключаем маршрут по умолчанию для интерфейса eth0 (10.0.2.15 - это сеть по умолчанию виртуалбокса) и прописываем шлюз по умолчанию для другого интерфейса, который смотрит в centralRouter. (более подробная информация содержится в вагрант файле)

#### Схема:

![image](https://raw.githubusercontent.com/staybox/otus_dz17/master/screenshots/filtration.png)

Запуск
git clone git@github.com:marozov/iptables.git && cd iptables && vagrant up
