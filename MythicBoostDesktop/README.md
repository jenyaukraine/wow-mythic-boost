# MythicBoost Desktop

Desktop-оверлей для World of Warcraft: получает заявки в группу через Overwolf GEP, объединяет публичные данные Raider.IO и Warcraft Logs и показывает полную карточку каждого участника.

## Что уже работает

- автоматическое появление окна при новой заявке в поиск группы;
- вся готовая группа в верхней полосе, переключение игрока одним кликом;
- общий M+ рейтинг, item level и восемь лучших ключей;
- рейдовый прогресс;
- Warcraft Logs: лучший/медианный parse, урон и число убийств по боссам;
- быстрая цветовая оценка кандидата;
- ручное обновление без использования старого Raider.IO-кэша;
- тестовый режим с полностью заполненной демонстрационной группой;
- секрет Warcraft Logs хранится через Windows `safeStorage`.

## Запуск интерфейса с тестовыми данными

```powershell
pnpm install
pnpm start:mock
```

## Запуск с реальным World of Warcraft

Для GEP нужен Developer Key приложения Overwolf. После создания приложения в Developer Console:

```powershell
$env:OW_DEV_KEY = "ваш-key"
pnpm start
```

Открой WoW и окно поиска заранее собранных групп. Событие `group_applicants` само наполнит оверлей и откроет его при новой заявке.

Для таблицы урона создай client credentials в Warcraft Logs и вставь Client ID/Secret в настройки MythicBoost. Raider.IO работает без отдельного ключа.

## Сборка

```powershell
pnpm build
```

Готовый установщик создаётся в `dist`. Без ключей он собирается как unsigned development build: окно и mock-интерфейс работают, но пакеты GEP/overlay не активируются. Публичное распространение настоящего injected overlay требует зарегистрированного Overwolf App UID и подписи.
