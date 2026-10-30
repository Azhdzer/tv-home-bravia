# tv-home-bravia

**Быстрый и чистый Sony BRAVIA KD-55XF9005.** Отключает по Wi-Fi рекламу, телеметрию и мусор и ставит
крошечный домашний экран в стиле Apple TV с меняющимися обоями-пейзажами. Всё обратимо: пакеты
отключаются, но не удаляются.

Это адаптация проекта [mihirgupta0900/tv-home](https://github.com/mihirgupta0900/tv-home) (он сделан для
TCL Google TV и macOS) под KD-55XF9005 и Windows.

**Пошаговое руководство: [ИНСТРУКЦИЯ.md](ИНСТРУКЦИЯ.md).** Начинайте с него.

**Статус: на настоящем телевизоре проект ещё не запускался.** Проверены сборка APK на Windows 10, логика скриптов на
программной имитации ТВ и совместимость кода с Android 7–9. Настройки взяты у владельцев телевизоров на той же
платформе (XBR-65X900F, KD-55XF8096, KD-65A8F). Если вы проверите проект на своём ТВ, расскажите о результате в Issues.

## Коротко

На ТВ включите отладку: *Настройки устройства → Об устройстве →* 7 раз нажмите на *Сборка*, затем
*Для разработчиков → Отладка по USB*. Затем на компьютере в PowerShell (путь без пробелов и кириллицы):

```powershell
git clone https://github.com/Azhdzer/tv-home-bravia.git D:\tv-home-bravia
cd D:\tv-home-bravia
.\setup.ps1                                                          # Python-клиент ADB, JDK 17, Android SDK
tools\find-tv.ps1                                                    # находит ТВ и запоминает его IP
tools\venv\Scripts\python.exe -I tools\tv.py --probe                 # модель и версия Android
tools\disable.ps1 examples\sony-bravia-kd55xf9005\debloat.txt        # отключает мусор (сначала делает копию)
launcher\build-and-install.ps1                                       # собирает и ставит лаунчер
```

Откат всего: `tools\restore.ps1 examples\sony-bravia-kd55xf9005\debloat.txt`.

## Чем отличается от оригинала

| Что | В оригинале | Здесь | Зачем |
|---|---|---|---|
| Версия Android | `minSdk 30` (Android 11) | `minSdk 24`, сборка под API 28 | На XF90 Android 9. Оригинальный APK на него просто не установится |
| Компьютер | macOS (Homebrew, `nc`, `dns-sd`) | Windows 10/11 (PowerShell) | Скрипты переписаны, JDK и SDK ставятся в папку проекта |
| Домашний экран | Google TV (`launcherx`) | Android TV (`com.google.android.tvlauncher`) | Другой лаунчер и другой порядок передачи кнопки Home |
| Мастер настройки | Отключается всегда | Не трогается | На этой платформе он не перехватывает Home, а на BRAVIA 9 II его отключение стирало Wi-Fi |
| Входы и ТВ | `com.tcl.tv` | `com.sony.dtv.tvx` | У Sony это приложение показывает и HDMI, и эфир |
| Подключение кабелем | Показывает «Offline» | Показывает «Ethernet» | XF90 часто подключён по кабелю |
| Интерфейс | Английский | Русский при русском языке ТВ, иначе английский | Дата и так была на языке системы |
| Защита | Нет | Копия перед изменениями, отказ отключать критичные пакеты, откат при неудачной передаче Home | Если ТВ останется без домашнего экрана, спасти его можно только по ADB |

## Что здесь

| Путь | Что это |
|---|---|
| [ИНСТРУКЦИЯ.md](ИНСТРУКЦИЯ.md) | Полная пошаговая инструкция с проверками и решением проблем |
| [PROMPT.md](PROMPT.md) | Готовый запрос, если хотите поручить всё Claude Code |
| [setup.ps1](setup.ps1) | Разовая настройка компьютера |
| [examples/sony-bravia-kd55xf9005/debloat.txt](examples/sony-bravia-kd55xf9005/debloat.txt) | Что отключается. Прочитайте: часть функций оставлена на ваш выбор |
| [launcher/](launcher/) | Домашний экран: 4,7 МБ с обоями, чистый Android, без сети и фоновых служб |
| [launcher/res/values/config.xml](launcher/res/values/config.xml) | Приложения в доке, скрытые приложения, приложение ТВ, число колонок |
| [launcher/build-and-install.ps1](launcher/build-and-install.ps1) | Сборка и установка лаунчера |
| [tools/tv.py](tools/tv.py) | ADB-клиент на чистом Python: команды, скриншоты, загрузка APK |
| [tools/find-tv.ps1](tools/find-tv.ps1) | Поиск ТВ в сети |
| [tools/backup.ps1](tools/backup.ps1) | Снимок состояния ТВ |
| [tools/disable.ps1](tools/disable.ps1), [tools/restore.ps1](tools/restore.ps1) | Применить и отменить список |
| [tools/type.ps1](tools/type.ps1) | Набор текста на экранной клавиатуре ТВ с компьютера (только латиница) |

## Лаунчер

- Часы, приветствие и дата слева вверху. Справа кнопки **Входы** (HDMI, видео, эфирное ТВ), **Wi-Fi** и **Настройки**.
- Док с любимыми приложениями. Над ним название приложения в фокусе и свечение цвета его баннера. Кнопка «вниз» открывает сетку остальных приложений.
- 12 фотографий природы сменяются каждые 10 минут. Заменить их можно в `launcher/assets/wallpapers/` (JPEG 1920×1080, авторы указаны в `launcher/WALLPAPER-CREDITS.md`).
- Предсказуемая навигация пультом, запоминает последнюю плитку, сам замечает новые приложения.

## Благодарности

В основе лежит [mihirgupta0900/tv-home](https://github.com/mihirgupta0900/tv-home). Сведения о пакетах Sony и ловушках
платформы взяты из наблюдений владельцев в [Gathin23/cleanyourtv](https://github.com/Gathin23/cleanyourtv)
(XBR-65X900F, KD-55XF8096, KD-65A8F) и [mundodigitalpro/sony-bravia-kd55xf8096](https://github.com/mundodigitalpro/sony-bravia-kd55xf8096).
Код распространяется по лицензии MIT, см. [LICENSE](LICENSE). У фотографий обоев свои лицензии, см.
[launcher/WALLPAPER-CREDITS.md](launcher/WALLPAPER-CREDITS.md).
