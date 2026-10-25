# UltraCorrect 0.1.x — сведения для сохранения совместимости

Проверено 25.10.2026 по исходникам, сохранённой сборке и Связке ключей. Личные правила и закрытые ключи не читались и не копировались.

- Зафиксированный main: `baf5f6fbc04f74055cfdb412b3366a57ce064241`.
- Локальные ссылки: тег `legacy-0.1.23`, ветка `legacy/0.1`; обе указывают на этот коммит. Push не выполнялся.
- Bundle ID: `local.ultracorrect.mac`, версия `0.1.23`, build `30` (`Packaging/Info.plist`).

## Хранилище личных правил

Путь по умолчанию: `~/Library/Application Support/UltraCorrect/personal.json` (`Sources/UltraCorrect/LocalLanguageService.swift:29`).

Формат: JSON, Swift Codable, `schema = 1`; верхний уровень `epoch`, `collecting`, `records`, опциональный `undo`. `records` — словарь по токену, записи содержат `version`, `forbidden`, `protectedWord`, `activeTarget`, `manualTarget`, `conflicted`, счётчики `manual/reverts/repeats`; опциональные дополнения `bufferManual`, `bufferRepeats`, `replacementEvidence`, `protectionEvidence`. Счётчики содержат UUID эпизодов и сессий. `undo` хранит `word`, `before`, `afterVersion`, `episode`.

Источник схемы: `Sources/UltraCorrectCore/PersonalLearning.swift:44`. Загрузка — JSONDecoder, верхний предел 10 MiB и 100 000 записей. Для импорта в итерации 04 следует опираться на точный исходник в legacy-теге, не на реальные данные пользователя.

## Подпись

- Имя: `UltraCorrect Local Development`.
- SHA-1 сертификата: `28107DCFD48A5B3B21DC6726144ACFFDDCE44E0A`.
- В Связке ключей найдена валидная codesigning identity с этим SHA-1 (`security find-identity -v -p codesigning`).
- Сохранённая сборка `dist/UltraCorrect-0.1.23-build30.app` подписана этой идентичностью. `codesign -d -r-` показывает тот же bundle ID и SHA-1 сертификата; `codesign --verify --strict` завершился успешно.
- Legacy-сборка не имеет Hardened Runtime (`flags=0x0`). Для 2.x необходимо включить его, сохранив идентичность. Новые сборки в шаге 0 не создавались.
- Связка ключей и закрытый ключ не изменялись. Наличие действующей подписи не означает, что проверено разрешение на будущую операцию подписания.

## Эталонный словарь

Путь в `legacy-0.1.23`: `Sources/UltraCorrectCore/Resources/Language/normative.utf8`.

Git blob: `99cca1d25635560f8cd58efc278dc7851ffa01cb`; размер: 33 011 780 байт. Данные не переносились в новый код.
