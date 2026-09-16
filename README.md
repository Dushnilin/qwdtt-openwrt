# qWDTT OpenWrt

RAW-IP клиент qWDTT для роутеров OpenWrt. Он поднимает интерфейс `qwdtt0` и
направляет через туннель IPv4-трафик устройств локальной сети. Сам роутер
сохраняет прямой доступ к WAN, поэтому соединения с VK TURN не зацикливаются.

Поддерживается только RAW-IP. WireGuard и SOCKS в этой сборке намеренно не
включены.

## Что понадобится

- Роутер с OpenWrt 23.05, 24.10, 25.12+ с `procd` и `firewall4`.
- Пакеты `ip-full`, `kmod-tun`, `ca-bundle` (установщик может установить их автоматически).
- Сервер qWDTT с включённым RAW-слушателем (обычно UDP-порт `56003`).
- Данные подключения: адрес сервера, пароль и хеш звонка VK.

## Быстрый запуск

### Вариант 1. Быстрая онлайн-установка одной командой

Выполните на роутере в терминале:

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/Dushnilin/qwdtt-openwrt/master/install.sh)"
```

Скрипт сам определит архитектуру вашего процессора, скачает нужный релиз и установит клиент в систему.

---

### Вариант 2. Ручная установка архива

1. Откройте [Releases](../../releases/latest) и скачайте архив для архитектуры своего роутера.
2. Распакуйте архив на роутере и запустите установку:

   ```sh
   tar -xzf qwdtt-openwrt-aarch64.tar.gz
   cd qwdtt-openwrt-aarch64
   ./install.sh
   ```

3. Откройте `/etc/qwdtt/config.json` и заполните `peer`, `hashes` и `password`.
   Пароль и хеш нельзя публиковать или отправлять посторонним.
4. Включите сервис:

   ```sh
   uci set qwdtt.main.enabled='1'
   uci commit qwdtt
   /etc/init.d/qwdtt start
   ```

## Проверка

Логи подключения:

```sh
logread -e qwdtt
```

Рабочее подключение пишет `RAW-конфиг получен`, затем `TUN подключён, трафик
пошёл`. Проверить интерфейс и правило маршрутизации можно так:

```sh
ip addr show qwdtt0
ip rule show
ip route show table 51820
```

Проверка создания TUN без данных VK и сервера:

```sh
/usr/bin/qwdtt-client -rawtun-self-test 10.70.0.2
```

## Настройка

Пример файла находится в [`files/etc/qwdtt/config.json`](files/etc/qwdtt/config.json).

`lan_interface` по умолчанию — `br-lan`. Если в вашей сборке OpenWrt LAN
называется иначе, поменяйте это поле. При изменении `tun_name` нужно также
изменить устройство зоны `qwdtt` в конфигурации firewall.

Остановить клиент:

```sh
/etc/init.d/qwdtt stop
```

## Поддерживаемые архитектуры

Сборка ведётся через GitHub Actions под все актуальные архитектуры OpenWrt:

| Артефакт | Архитектура OpenWrt / Go | Примеры устройств |
| --- | --- | --- |
| `x86_64` | `x86_64` (amd64) | Мини-ПК, серверы, роутеры x86, виртуалки (Proxmox, ESXi) |
| `i386` | `x86` (32-bit x86) | Старые 32-битные x86-роутеры (Geode, VIA, ALIX) |
| `aarch64` | `aarch64` (arm64) | MediaTek Filogic (MT7981/MT7986), Rockchip RK3328/RK3399/RK3568, Raspberry Pi 4/5 |
| `armv7` | `arm_cortex-a7_neon-vfpv4` / `v7` | Qualcomm IPQ40xx, IPQ806x, Broadcom BCM53xx, Marvell Armada 38x |
| `armv6` | `arm_arm1176jzf-s_vfp` / `v6` | Raspberry Pi 1, Raspberry Pi Zero |
| `armv5` | `arm926ej-s` / `v5` | Marvell Kirkwood, Orion |
| `mipsel` | `mipsel_24kc` (softfloat) | MediaTek MT7621, MT7628, MT7620, RT305x (Keenetic, Xiaomi и др.) |
| `mipsel_hardfloat` | `mipsel` (hardfloat) | MIPS little-endian с аппаратным FPU |
| `mips` | `mips_24kc` (softfloat) | Atheros AR7xxx/AR9xxx, ath79, Qualcomm QCA953x/955x/956x, Realtek |
| `mips_hardfloat` | `mips` (hardfloat) | MIPS big-endian с аппаратным FPU |
| `mips64` | `mips64` (big-endian) | Cavium Octeon (Ubiquiti EdgeRouter Lite, EdgeRouter 4/6/8) |
| `mips64el` | `mips64le` (little-endian) | Cavium Octeon / Loongson |
| `riscv64` | `riscv64` | Allwinner D1, StarFive JH7110, Milk-V и др. |
