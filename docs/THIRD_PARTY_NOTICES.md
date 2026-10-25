# Внешние компоненты и данные

В итерации 01a нет сторонних пакетов Swift, словарей, корпусов и нейросетевых моделей. `Resources/manifest.json` содержит пустой список ресурсов с заданной схемой учёта. Словарь 0.1.x не переносился.

Таблицы `Tests/Fixtures/layouts/*.json` — результаты собственного инструмента `uc-layout-dump`, вызывающего публичные TIS/UCKeyTranslate API установленной macOS. Системные файлы раскладок и SDK не распространяются. Для проверки происхождения публикуются хеши таблиц в evidence.json. Это платформенные тестовые фикстуры, не скачиваемые языковые ресурсы.

`docs/SPEC.md`, `docs/PROCESS.md`, `docs/ANALYSIS.md`, `docs/iterations/01a/TZ.md` и `tools/reference/kbd_estimate.py` предоставлены пользователем для этого проекта и перенесены без изменений. SHA-256 — в `docs/iterations/01a/input-hashes.json`.

Инструменты среды (не встраиваются в приложение): Swift/Foundation/XCTest — https://github.com/swiftlang/swift (Apache-2.0 с Runtime Library Exception); XcodeGen — https://github.com/yonaskolb/XcodeGen (MIT); Gitleaks — https://github.com/gitleaks/gitleaks (MIT). Apple SDK и системные библиотеки поставляются Apple по условиям Xcode/macOS. Их бинарные файлы в репозиторий и релиз не включаются.

Иконка-заглушка создана в этом проекте, сторонних изображений нет.
