# WGMenu — Утилита управления конфигурацией WireGuard

`WGMenu` — это интерактивный Bash-скрипт для управления блоками `[Peer]` в конфигурационном файле WireGuard (`wghub.conf`). Он позволяет выполнять резервное копирование, комментирование, удаление и поиск peer-блоков, а также перезапуск WireGuard с обновлённой конфигурацией.

---

## 📦 Возможности

- 📋 Отображение всех peer-блоков в виде таблицы
- 🔍 Поиск по содержимому блока, включая подписи и заметки (`# Note:`)
- ✏️ Комментирование и разкомментирование peer-блоков
- ❌ Удаление peer-блоков
- 🔁 Перезапуск `wg-quick` после изменений
- 💾 Автоматическое создание резервной копии перед работой (`wghub.conf.bak`)
- 🧾 Поддержка аннотированных заметок (Note) перед блоком

---

## ⚙️ Формат конфигурации

Каждый `[Peer]` блок должен заканчиваться строкой `AllowedIPs = ...`.

Дополнительно, перед блоком можно указать комментарий в виде:
```ini
# Note: Girlfriend
# 01: user1 > wgclient_user1.conf
[Peer]
PublicKey = ...
...
AllowedIPs = ...
```
## Пример вывода пользователй

 №   | Подпись (и заметка)            | PublicKey                    | PresharedKey                | AllowedIPs         
-----|--------------------------------|------------------------------|-----------------------------|--------------------
 1   | user1                          | ddfglkw4lknweEt z...         | HEWEHfdseu8wyGHF...         | 10.0.0.2/32        
 2   | *** user2 (Отключен) ***       | *                            | *                           | *                  

## 🚀 Как использовать

Помести скрипт рядом с файлом wghub.conf

Убедись, что файл имеет права на выполнение:

```
chmod +x wgmenu.sh
```

Запусти скрипт:

```
./wgmenu.sh
```

## 🔐 Совместимость

Linux (Bash shell)

Требует wg-quick установленный и доступный в PATH
