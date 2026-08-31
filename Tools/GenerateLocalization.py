"""Generate static MythicBoost locale tables and wrap Russian UI literals.

This is a maintainer tool, not a runtime dependency of the addon.  It keeps the
Russian source string as the stable key, protects WoW/printf markup while it is
translated, and writes ordinary Lua tables that work without any libraries.
"""

from __future__ import annotations

import json
import os
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from deep_translator import GoogleTranslator
from luaparser import ast, astnodes


ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / "MythicBoost"
CACHE = ROOT / "Tools" / "localization-cache.json"
CYRILLIC = re.compile(r"[А-яЁё]")
TOKEN = re.compile(
    r"\|c[0-9a-fA-F]{8}|\|cff%[-+ #0\d.*]*s|\|r|\|A:[^|]*\|a|\|T[^|]*\|t|"
    r"%[-+ #0\d.*]*[cdeEfgGiouXxqs]|%%|/mb(?:\s+[A-Za-z]+)*"
)
EXCLUDED_FILES = {"Modules/RealmData.lua"}
NO_WRAP = {"искусственного интеллекта"}


MANUAL = {
    "en": {
        "АК": "AF", "СД": "BV", "БН": "DN", "ЗД": "MR",
        "АШ": "VA", "РО": "RLP", "ХС": "TJS", "ГК": "KR",
        "Т": "T", "Х": "H", "Б": "D",
        "Л": "H",
        "НЕ ПРОШЛО": "DID NOT PASS", "НЕ ПРОШЛИ ФИЛЬТРЫ": "DID NOT PASS FILTERS",
        "НЕ ПРОШЛИ ФИЛЬТРЫ · %d": "DID NOT PASS FILTERS · %d",
        "Недоступная группа": "Unavailable group", "Недоступно": "Unavailable",
        "не прошло фильтр: %s": "did not pass filter: %s", "причина неизвестна": "reason unknown",
        "%d подходят  •  %d ниже  •  %d всего": "%d suitable  •  %d below  •  %d total",
        "подходит групп: %d, ниже фильтров: %d": "suitable groups: %d, below filters: %d",
        "ГРУППЫ": "GROUPS",
        "ошибка чтения результата": "result read error",
        "строка поиска %s не разобрана: %s": "search result %s could not be read: %s",
        "Собрать свой ключ": "List my key",
        "твой ключ": "your key",
        "Серьёзный": "Serious",
        "Только онлайн": "Online only",
        "Пригласить": "Invite",
        "Группа уже создана": "Group already listed",
        "Группа создана": "Group listed",
        "Штатное окно": "Default window",
        "%dч": "%dh", "%dм": "%dm", " %dс": " %ds",
        "x%d  -%sс": "x%d  -%ss", "Подожди %dс": "Wait %ds", "%d з": "%d g",
        "Герб": "Crest", "ГЕРБЫ": "CRESTS", "Герб #": "Crest #", "герб": "crest",
        "Искатель": "Adventurer", "искател": "adventur",
        "Защитник": "Champion", "защитник": "champion",
        "Герой": "Hero", "геро": "hero",
        "Эпоха": "Myth", "эпох": "myth",
        "^Маревый герб%s+": "^Duskcrest%s+",
        "Проходок этого данжа": "Runs in this dungeon",
        "Лучший забег: %s   •   текущий прогноз: %s": "Best run: %s   •   current estimate: %s",
        "Импортирована история MPlusTimer: %d лучших забегов.": "Imported MPlusTimer history: %d best runs.",
        "Свой мифический ключ не найден.": "Your Mythic Keystone was not found.",
        "Копировать ссылку Warcraft Logs": "Copy Warcraft Logs URL",
        "Ссылка Warcraft Logs — %s": "Warcraft Logs URL — %s",
        "Автоматически вставлять эпохальный ключ": "Automatically insert Mythic Keystone",
        "Оформлять миникарту MythicBoost": "Style minimap with MythicBoost",
        "Написать": "Whisper",
        "Позвать": "Invite",
        "Приглашения, эпохальные ключи и умный клик": "Invites, Mythic Keystones and Smart Click",
        "Подземелье и +уровень берутся из камня, режим — «Серьёзный».": "Dungeon and +level come from your Keystone; playstyle is “Serious”.",
        "Зарегистрирован свой ключ +%d, режим «Серьёзный».": "Listed your +%d Keystone with “Serious” playstyle.",
        "Повышение ключа": "Keystone upgrade",
        "Ключ от": "Min key", "Ключ до": "Max key", "Ключей +10 от": "Min +10 keys",
        "Рейтинг от": "Min rating", "Рейтинг до": "Max rating",
        "Лекарь уже в группе": "Healer already in group",
        "в группе нет лекаря": "no healer in group",
        "3 - ЛЕКАРЬ И ОПАСНАЯ ЦЕЛЬ": "3 - HEALER & DANGEROUS TARGET",
        "3 - Лекарь и опасная цель": "3 - Healer & dangerous target",
        "Не хватает гербов: %d      Золото: %s": "Missing crests: %d      Gold: %s",
        "Улучшать нечего: игра не назвала ни одного герба для надетых вещей.": "Nothing to upgrade: the game returned no crest costs for your equipped items.",
        "Журнал ": "Log ", "Журнал пуст.": "Log is empty.", "Журнал очищен.": "Log cleared.",
        "Журнал выключен. Включить: /mb log on": "Logging is disabled. Enable it with: /mb log on",
        "Журнал ошибок": "Error log", "Журнал ошибок очищен.": "Error log cleared.",
        " будет пересобран после боя.": " will be reloaded after combat.", " пересобран.": " reloaded.",
        "Не удалось пересобрать ": "Failed to reload ",
        "MinimalUI: событие %s недоступно в этом клиенте": "MinimalUI: event %s is unavailable in this client",
        "Клик — снять сумку": "Click — unequip bag",
        "Только просмотр": "View only",
        "ОСНОВНОЕ": "GENERAL", "Основное": "General",
        "Поиск → сбор пати → история: ядро всегда работает без замены интерфейса": "Search → build a party → history: the core works without replacing your UI",
        "ОСНОВНОЙ СЦЕНАРИЙ": "CORE WORKFLOW",
        "1. Найди подходящую группу.  2. Собери состав на свой ключ.  3. После прохождения сохрани полезных напарников и разбор забега.": "1. Find the right group.  2. Build a party for your key.  3. Save useful teammates and the run review.",
        "ПОЛНОТА ВЫДАЧИ": "COMPLETE RESULTS",
        "Показывать серым группы, не прошедшие фильтры": "Show groups below filters in grey",
        "Разрешать ручную заявку в серые группы": "Allow manual applications to grey groups",
        "ПОМОЩЬ": "HELP", "Показать краткую инструкцию": "Show quick guide",
        "Автодействия и замены интерфейса выключены на новом профиле. Включай только то, что действительно нужно.": "Automatic actions and UI replacements are off on a new profile. Enable only what you need.",
        "Скрывать стандартные фреймы игрока и цели": "Hide default player and target frames",
        "Стандартные фреймы Blizzard": "Default Blizzard frames",
        "Выключи галочку, если хочешь оставить стандартные фреймы рядом с компактными.": "Clear this option to keep the default frames alongside the compact frames.",
        "Перехватывать Lua-ошибки в журнал": "Capture Lua errors in the log",
        "Перехват Lua-ошибок": "Lua error capture",
        "Ошибки Lua не показываются на экране, а сохраняются в журнале со счётчиком повторов.": "Lua errors are hidden on screen and saved in the log with repeat counts.",
        "Функция выключена по умолчанию. Не включай её одновременно с BugGrabber или BugSack.": "Off by default. Do not enable it together with BugGrabber or BugSack.",
        "Сохранять журнал между перезагрузками": "Keep the log between reloads",
        "СОСТОЯНИЕ": "STATUS",
        "Версия %s  •  Raider.IO: %s  •  журнал: %d / %d": "Version %s  •  Raider.IO: %s  •  log: %d / %d",
        "подключён": "connected", "не найден": "not found",
        "MythicBoost ведёт по трём шагам: найти группу, собрать пати и сохранить результат.": "MythicBoost follows three steps: find a group, build a party, and save the result.",
        "Подходящих групп нет. Ещё %d групп скрыты настройкой нижней серой секции.": "No suitable groups. %d more groups are hidden by the lower grey-section setting.",
        "АНАЛИЗ ИГРОКОВ": "PLAYER ANALYSIS",
        "Дополнять подсказки ключами и прогнозом игрока": "Add keys and player estimates to tooltips",
        "Отмечать сохранённых перспективных игроков": "Mark saved promising players",
        "Оптимизатор пяти заявок": "Five-application optimizer",
        "приоритет %d, средний RIO %d, найдено %d/%d": "priority %d, average RIO %d, found %d/%d",
        "План: %d здесь + %d активных вне текущего поиска": "Plan: %d here + %d active outside the current search",
        "Штрафа за смерти не было — ищи потери в маршруте, простоях и уроне.": "There was no death penalty — look for time lost to routing, downtime, and damage.",
        "твоя роль нужна": "your role is needed",
        "уверенность %d%%": "confidence %d%%",
        "уровень ключа приблизительный": "key level is approximate",
        "уровень ключа скрыт или оценён": "key level is hidden or estimated",
        "яды": "poisons",
        "Капсула": "Unit Frames",
        "КАПСУЛА И РЕСУРСЫ": "UNIT FRAMES & RESOURCES",
        "КАПСУЛА ИГРОКА И ЦЕЛИ": "PLAYER & TARGET FRAMES",
        "КВАДРАТЫ РЕСУРСА": "RESOURCE SEGMENTS",
        "АУРЫ": "AURAS",
        "Включить компактные капсулы": "Enable compact unit frames",
        "Точная настройка карточек игрока и цели, ресурсов и аур": "Fine-tune player and target frames, resources, and auras",
        "Комбо-поинты, руны, осколки душ, сила Света, ци, чародейские заряды и эссенция.": "Combo points, runes, soul shards, Holy Power, chi, Arcane Charges, and essence.",
        "Расстояние между ними": "Segment spacing",
        "Вернуть оформление по умолчанию": "Reset appearance to defaults",
        "СР. RIO": "AVG. RIO",
        "найдено %d/%d": "found %d/%d",
        "РЕЖИМ СКРИНШОТОВ": "SCREENSHOT MODE",
        "Скриншоты": "Screenshots",
        "АНОНИМНЫЕ ДЕМО-СЦЕНЫ": "ANONYMOUS DEMO SCENES",
        "Пять готовых анонимных сцен для страницы аддона": "Five ready-to-capture anonymous scenes for the addon page",
        "Демо закрывает остальной интерфейс. Все имена и значения вымышлены; данные персонажа, сервера и чата не используются.": "The demo covers the rest of the UI. All names and values are fictional; character, realm, and chat data are never used.",
        "ДЕМО · ВЫМЫШЛЕННЫЕ ИМЕНА · ЛИЧНЫЕ ДАННЫЕ СКРЫТЫ": "DEMO · FICTIONAL NAMES · PERSONAL DATA HIDDEN",
        "Выбери сцену кнопками 1–5 · Esc закрывает демо": "Choose a scene with buttons 1–5 · Esc closes the demo",
        "Закрыть демо": "Close demo",
        "1 · ОБЩИЙ ВИД": "1 · GENERAL VIEW",
        "2 · ТАНК ПОД ДАВЛЕНИЕМ": "2 · TANK UNDER PRESSURE",
        "3 · ЛЕКАРЬ И ОПАСНАЯ ЦЕЛЬ": "3 · HEALER & DANGEROUS TARGET",
        "4 · КОМБО И ДЕБАФФЫ": "4 · COMBO POINTS & DEBUFFS",
        "5 · ЧИСТЫЙ МИНИМАЛ": "5 · CLEAN MINIMAL",
        "Игрок и цель в спокойном боевом состоянии": "Player and target in a calm combat state",
        "Низкое здоровье, защитные эффекты и руны": "Low health, defensive effects, and runes",
        "Мана, критическое здоровье цели и эффект для рассеивания": "Mana, critical target health, and a dispellable effect",
        "Семь комбо-поинтов и плотная строка эффектов": "Seven combo points and a full row of effects",
        "Капсулы без лишних эффектов — для обложки и сравнения": "Clean frames without extra effects — ideal for a cover or comparison",
        "1 · Общий вид": "1 · General view",
        "2 · Танк под давлением": "2 · Tank under pressure",
        "3 · Лекарь и опасная цель": "3 · Healer & dangerous target",
        "4 · Комбо и дебаффы": "4 · Combo points & debuffs",
        "5 · Чистый минимал": "5 · Clean minimal",
        "Спокойная пара игрок/цель с ресурсом и базовыми аурами.": "A calm player/target pair with resource pips and basic auras.",
        "Низкое здоровье, защитные эффекты и шесть рун.": "Low health, defensive effects, and six runes.",
        "Мана, критическое здоровье и эффекты для рассеивания.": "Mana, critical health, and dispellable effects.",
        "Семь комбо-поинтов и плотная строка эффектов.": "Seven combo points and a full row of effects.",
        "Чистые капсулы без эффектов для обложки и сравнения.": "Clean frames without effects for a cover or comparison.",
        "ТВОЙ КЛЮЧ": "YOUR KEY",
        "вместе с": "with",
        "Состав пакетной заявки:": "Application party:",
        "Участник %d": "Member %d",
        "Пакетная заявка ×%d": "Group application ×%d",
    },
    "de": {
        "АК": "AF", "СД": "BV", "БН": "DN", "ЗД": "MR",
        "АШ": "VA", "РО": "RLP", "ХС": "TJS", "ГК": "KR",
        "Т": "T", "Х": "H", "Б": "S",
        "Л": "H",
        "НЕ ПРОШЛО": "NICHT GEFILTERT", "НЕ ПРОШЛИ ФИЛЬТРЫ": "NICHT DURCH DIE FILTER",
        "НЕ ПРОШЛИ ФИЛЬТРЫ · %d": "NICHT DURCH DIE FILTER · %d",
        "Недоступная группа": "Nicht verfügbare Gruppe", "Недоступно": "Nicht verfügbar",
        "не прошло фильтр: %s": "Filter nicht bestanden: %s", "причина неизвестна": "Grund unbekannt",
        "%d подходят  •  %d ниже  •  %d всего": "%d geeignet  •  %d unten  •  %d gesamt",
        "подходит групп: %d, ниже фильтров: %d": "geeignete Gruppen: %d, unter den Filtern: %d",
        "ГРУППЫ": "GRUPPEN",
        "ошибка чтения результата": "Fehler beim Lesen des Ergebnisses",
        "строка поиска %s не разобрана: %s": "Suchergebnis %s konnte nicht gelesen werden: %s",
        "Собрать свой ключ": "Eigenen Schlüssel anmelden",
        "твой ключ": "dein Schlüssel",
        "Серьёзный": "Ernsthaft",
        "Только онлайн": "Nur online",
        "Пригласить": "Einladen",
        "Группа уже создана": "Gruppe bereits angemeldet",
        "Группа создана": "Gruppe angemeldet",
        "Штатное окно": "Standardfenster",
        "%dч": "%dh", "%dм": "%dm", " %dс": " %ds",
        "x%d  -%sс": "x%d  -%ss", "Подожди %dс": "Warte %ds", "%d з": "%d G",
        "Герб": "Wappen", "ГЕРБЫ": "WAPPEN", "Герб #": "Wappen #", "герб": "wappen",
        "Искатель": "Abenteurer", "искател": "abenteurer",
        "ветеран": "veteran",
        "Защитник": "Champion", "защитник": "champion",
        "Герой": "Held", "геро": "held",
        "Эпоха": "Mythos", "эпох": "myth",
        "^Маревый герб%s+": "^Dämmerwappen%s+",
        "Проходок этого данжа": "Läufe in diesem Dungeon",
        "Лучший забег: %s   •   текущий прогноз: %s": "Bester Lauf: %s   •   aktuelle Schätzung: %s",
        "Импортирована история MPlusTimer: %d лучших забегов.": "MPlusTimer-Verlauf importiert: %d beste Läufe.",
        "Свой мифический ключ не найден.": "Dein mythischer Schlüsselstein wurde nicht gefunden.",
        "Копировать ссылку Warcraft Logs": "Warcraft-Logs-Link kopieren",
        "Ссылка Warcraft Logs — %s": "Warcraft-Logs-Link — %s",
        "Автоматически вставлять эпохальный ключ": "Mythischen Schlüsselstein automatisch einfügen",
        "Оформлять миникарту MythicBoost": "Minikarte mit MythicBoost gestalten",
        "Написать": "Flüstern",
        "Позвать": "Einladen",
        "Приглашения, эпохальные ключи и умный клик": "Einladungen, mythische Schlüsselsteine und Smart Click",
        "Подземелье и +уровень берутся из камня, режим — «Серьёзный».": "Dungeon und +Stufe kommen von deinem Schlüsselstein; Spielstil ist „Ernsthaft“.",
        "Зарегистрирован свой ключ +%d, режим «Серьёзный».": "Eigenen +%d-Schlüsselstein mit Spielstil „Ernsthaft“ angemeldet.",
        "Повышение ключа": "Schlüsselstein-Aufwertung",
        "Ключ от": "Schlüssel min.", "Ключ до": "Schlüssel max.", "Ключей +10 от": "+10-Schlüssel min.",
        "Рейтинг от": "Wertung min.", "Рейтинг до": "Wertung max.",
        "Лекарь уже в группе": "Heiler bereits in der Gruppe",
        "в группе нет лекаря": "kein Heiler in der Gruppe",
        "3 - ЛЕКАРЬ И ОПАСНАЯ ЦЕЛЬ": "3 - HEILER & GEFÄHRLICHES ZIEL",
        "3 - Лекарь и опасная цель": "3 - Heiler & gefährliches Ziel",
        "Не хватает гербов: %d      Золото: %s": "Fehlende Wappen: %d      Gold: %s",
        "Улучшать нечего: игра не назвала ни одного герба для надетых вещей.": "Nichts aufzuwerten: Das Spiel lieferte keine Wappenkosten für deine angelegten Gegenstände.",
        "Журнал ": "Protokoll ", "Журнал пуст.": "Protokoll ist leer.", "Журнал очищен.": "Protokoll geleert.",
        "Журнал выключен. Включить: /mb log on": "Protokollierung ist deaktiviert. Aktivieren mit: /mb log on",
        "Журнал ошибок": "Fehlerprotokoll", "Журнал ошибок очищен.": "Fehlerprotokoll geleert.",
        " будет пересобран после боя.": " wird nach dem Kampf neu geladen.", " пересобран.": " neu geladen.",
        "Не удалось пересобрать ": "Neuladen fehlgeschlagen: ",
        "MinimalUI: событие %s недоступно в этом клиенте": "MinimalUI: Ereignis %s ist in diesem Client nicht verfügbar",
        "Клик — снять сумку": "Klick — Tasche ablegen",
        "Только просмотр": "Nur ansehen",
        "ОСНОВНОЕ": "ALLGEMEIN", "Основное": "Allgemein",
        "Поиск → сбор пати → история: ядро всегда работает без замены интерфейса": "Suche → Gruppe bilden → Verlauf: Der Kern funktioniert ohne UI-Ersetzung",
        "ОСНОВНОЙ СЦЕНАРИЙ": "KERNABLAUF",
        "1. Найди подходящую группу.  2. Собери состав на свой ключ.  3. После прохождения сохрани полезных напарников и разбор забега.": "1. Finde die passende Gruppe.  2. Stelle eine Gruppe für deinen Schlüssel zusammen.  3. Speichere gute Mitspieler und die Laufanalyse.",
        "ПОЛНОТА ВЫДАЧИ": "VOLLSTÄNDIGE ERGEBNISSE",
        "Показывать серым группы, не прошедшие фильтры": "Gruppen unter den Filtern grau anzeigen",
        "Разрешать ручную заявку в серые группы": "Manuelle Anmeldung bei grauen Gruppen erlauben",
        "ПОМОЩЬ": "HILFE", "Показать краткую инструкцию": "Kurzanleitung anzeigen",
        "Автодействия и замены интерфейса выключены на новом профиле. Включай только то, что действительно нужно.": "Automatische Aktionen und UI-Ersetzungen sind bei neuen Profilen aus. Aktiviere nur, was du brauchst.",
        "Скрывать стандартные фреймы игрока и цели": "Standard-Spieler- und Zielfenster ausblenden",
        "Стандартные фреймы Blizzard": "Blizzard-Standardfenster",
        "Выключи галочку, если хочешь оставить стандартные фреймы рядом с компактными.": "Deaktiviere diese Option, um die Standardfenster neben den kompakten zu behalten.",
        "Перехватывать Lua-ошибки в журнал": "Lua-Fehler im Protokoll erfassen",
        "Перехват Lua-ошибок": "Lua-Fehlererfassung",
        "Ошибки Lua не показываются на экране, а сохраняются в журнале со счётчиком повторов.": "Lua-Fehler werden nicht angezeigt, sondern mit Wiederholungszähler im Protokoll gespeichert.",
        "Функция выключена по умолчанию. Не включай её одновременно с BugGrabber или BugSack.": "Standardmäßig aus. Nicht zusammen mit BugGrabber oder BugSack aktivieren.",
        "Сохранять журнал между перезагрузками": "Protokoll zwischen Neuladungen behalten",
        "СОСТОЯНИЕ": "STATUS",
        "Версия %s  •  Raider.IO: %s  •  журнал: %d / %d": "Version %s  •  Raider.IO: %s  •  Protokoll: %d / %d",
        "подключён": "verbunden", "не найден": "nicht gefunden",
        "MythicBoost ведёт по трём шагам: найти группу, собрать пати и сохранить результат.": "MythicBoost folgt drei Schritten: Gruppe finden, Gruppe bilden und Ergebnis speichern.",
        "Подходящих групп нет. Ещё %d групп скрыты настройкой нижней серой секции.": "Keine passenden Gruppen. %d weitere Gruppen sind durch die Einstellung der grauen Sektion verborgen.",
        "АНАЛИЗ ИГРОКОВ": "SPIELERANALYSE",
        "Дополнять подсказки ключами и прогнозом игрока": "Tooltips um Schlüssel und Spielerprognose ergänzen",
        "Отмечать сохранённых перспективных игроков": "Gespeicherte vielversprechende Spieler markieren",
        "Оптимизатор пяти заявок": "Optimierer für fünf Anmeldungen",
        "приоритет %d, средний RIO %d, найдено %d/%d": "Priorität %d, durchschnittliche RIO %d, gefunden %d/%d",
        "План: %d здесь + %d активных вне текущего поиска": "Plan: %d hier + %d aktive außerhalb der aktuellen Suche",
        "Штрафа за смерти не было — ищи потери в маршруте, простоях и уроне.": "Keine Zeitstrafe durch Tode — suche Verluste bei Route, Leerlauf und Schaden.",
        "твоя роль нужна": "deine Rolle wird gebraucht",
        "уверенность %d%%": "Zuverlässigkeit %d%%",
        "уровень ключа приблизительный": "Schlüsselstufe ungefähr",
        "уровень ключа скрыт или оценён": "Schlüsselstufe verborgen oder geschätzt",
        "яды": "Gifte",
        "Капсула": "Einheitenfenster",
        "КАПСУЛА И РЕСУРСЫ": "EINHEITENFENSTER & RESSOURCEN",
        "КАПСУЛА ИГРОКА И ЦЕЛИ": "SPIELER- & ZIELFENSTER",
        "КВАДРАТЫ РЕСУРСА": "RESSOURCENSEGMENTE",
        "АУРЫ": "AUREN",
        "Включить компактные капсулы": "Kompakte Einheitenfenster aktivieren",
        "Точная настройка карточек игрока и цели, ресурсов и аур": "Spieler- und Zielfenster, Ressourcen und Auren genau anpassen",
        "Комбо-поинты, руны, осколки душ, сила Света, ци, чародейские заряды и эссенция.": "Combopunkte, Runen, Seelensplitter, Heilige Kraft, Chi, Arkane Aufladungen und Essenz.",
        "Расстояние между ними": "Segmentabstand",
        "Вернуть оформление по умолчанию": "Darstellung zurücksetzen",
        "СР. RIO": "Ø RIO",
        "найдено %d/%d": "%d/%d gefunden",
        "РЕЖИМ СКРИНШОТОВ": "SCREENSHOT-MODUS",
        "Скриншоты": "Screenshots",
        "АНОНИМНЫЕ ДЕМО-СЦЕНЫ": "ANONYME DEMO-SZENEN",
        "Пять готовых анонимных сцен для страницы аддона": "Fünf fertige anonyme Szenen für die Addon-Seite",
        "Демо закрывает остальной интерфейс. Все имена и значения вымышлены; данные персонажа, сервера и чата не используются.": "Die Demo verdeckt die restliche Benutzeroberfläche. Alle Namen und Werte sind erfunden; Charakter-, Realm- und Chatdaten werden nie verwendet.",
        "ДЕМО · ВЫМЫШЛЕННЫЕ ИМЕНА · ЛИЧНЫЕ ДАННЫЕ СКРЫТЫ": "DEMO · ERFUNDENE NAMEN · PERSÖNLICHE DATEN AUSGEBLENDET",
        "Выбери сцену кнопками 1–5 · Esc закрывает демо": "Szene mit den Tasten 1–5 wählen · Esc schließt die Demo",
        "Закрыть демо": "Demo schließen",
        "1 · ОБЩИЙ ВИД": "1 · GESAMTANSICHT",
        "2 · ТАНК ПОД ДАВЛЕНИЕМ": "2 · TANK UNTER DRUCK",
        "3 · ЛЕКАРЬ И ОПАСНАЯ ЦЕЛЬ": "3 · HEILER & GEFÄHRLICHES ZIEL",
        "4 · КОМБО И ДЕБАФФЫ": "4 · COMBO-PUNKTE & DEBUFFS",
        "5 · ЧИСТЫЙ МИНИМАЛ": "5 · KLARES MINIMALDESIGN",
        "Игрок и цель в спокойном боевом состоянии": "Spieler und Ziel in einer ruhigen Kampfsituation",
        "Низкое здоровье, защитные эффекты и руны": "Wenig Gesundheit, defensive Effekte und Runen",
        "Мана, критическое здоровье цели и эффект для рассеивания": "Mana, kritische Zielgesundheit und ein bannbarer Effekt",
        "Семь комбо-поинтов и плотная строка эффектов": "Sieben Combopunkte und eine volle Effektleiste",
        "Капсулы без лишних эффектов — для обложки и сравнения": "Klare Fenster ohne zusätzliche Effekte — ideal für Titelbild oder Vergleich",
        "1 · Общий вид": "1 · Gesamtansicht",
        "2 · Танк под давлением": "2 · Tank unter Druck",
        "3 · Лекарь и опасная цель": "3 · Heiler & gefährliches Ziel",
        "4 · Комбо и дебаффы": "4 · Combopunkte & Debuffs",
        "5 · Чистый минимал": "5 · Klares Minimaldesign",
        "Спокойная пара игрок/цель с ресурсом и базовыми аурами.": "Ruhige Spieler-/Zielansicht mit Ressourcensegmenten und grundlegenden Auren.",
        "Низкое здоровье, защитные эффекты и шесть рун.": "Wenig Gesundheit, defensive Effekte und sechs Runen.",
        "Мана, критическое здоровье и эффекты для рассеивания.": "Mana, kritische Gesundheit und bannbare Effekte.",
        "Семь комбо-поинтов и плотная строка эффектов.": "Sieben Combopunkte und eine volle Effektleiste.",
        "Чистые капсулы без эффектов для обложки и сравнения.": "Klare Fenster ohne Effekte für Titelbild oder Vergleich.",
        "ТВОЙ КЛЮЧ": "DEIN SCHLÜSSEL",
        "вместе с": "mit",
        "Состав пакетной заявки:": "Bewerbungsgruppe:",
        "Участник %d": "Mitglied %d",
        "Пакетная заявка ×%d": "Gruppenbewerbung ×%d",
    },
}


def relative(path: Path) -> str:
    return path.relative_to(ADDON).as_posix()


def string_nodes(path: Path):
    tree = ast.parse(path.read_text(encoding="utf-8"))
    for node in ast.walk(tree):
        if isinstance(node, astnodes.String) and CYRILLIC.search(node.raw):
            yield node


def collect() -> list[str]:
    values: set[str] = set()
    for path in sorted(ADDON.rglob("*.lua")):
        if relative(path) in EXCLUDED_FILES or path.name == "Localization.lua":
            continue
        values.update(node.raw for node in string_nodes(path))
    return sorted(values)


def mask(text: str):
    saved: list[str] = []

    def replace(match: re.Match[str]) -> str:
        saved.append(match.group(0))
        return f"ZXQ{len(saved) - 1}QXZ"

    return TOKEN.sub(replace, text), saved


def unmask(text: str, saved: list[str]) -> str:
    for index, value in enumerate(saved):
        text = re.sub(rf"ZXQ\s*{index}\s*QXZ", lambda _m, v=value: v, text, flags=re.I)
    return text


def translate_one(language: str, source: str) -> str:
    if source in MANUAL[language]:
        return MANUAL[language][source]
    protected, saved = mask(source)
    last_error = None
    for attempt in range(4):
        try:
            result = GoogleTranslator(source="ru", target=language).translate(protected)
            if result:
                return unmask(result, saved)
        except Exception as error:  # network/rate limit: retry with backoff
            last_error = error
            time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(f"translation failed for {source!r}: {last_error}")


def translate_all(values: list[str]) -> dict[str, dict[str, str]]:
    cache = json.loads(CACHE.read_text(encoding="utf-8")) if CACHE.exists() else {"en": {}, "de": {}}
    for language in ("en", "de"):
        cache.setdefault(language, {}).update(MANUAL[language])
        missing = [value for value in values if value not in cache[language]]
        print(f"{language}: {len(missing)} strings to translate", flush=True)
        with ThreadPoolExecutor(max_workers=6) as pool:
            futures = {pool.submit(translate_one, language, value): value for value in missing}
            for done, future in enumerate(as_completed(futures), 1):
                value = futures[future]
                cache[language][value] = future.result()
                if done % 25 == 0 or done == len(missing):
                    print(f"{language}: {done}/{len(missing)}", flush=True)
                    CACHE.write_text(json.dumps(cache, ensure_ascii=False, indent=2), encoding="utf-8")
        CACHE.write_text(json.dumps(cache, ensure_ascii=False, indent=2), encoding="utf-8")
    return cache


def lua_quote(value: str) -> str:
    return json.dumps(value, ensure_ascii=False).replace("\\/", "/")


def write_locale(values: list[str], translations: dict[str, dict[str, str]]) -> None:
    lines = [
        "local _, JP = ...",
        "",
        "-- Russian source strings are stable localization keys.  Unsupported",
        "-- clients use English; missing entries safely fall back to Russian.",
        "local locale = GetLocale and GetLocale() or \"enUS\"",
        "local translations",
        "",
        "if locale == \"deDE\" then",
        "    translations = {",
    ]
    for value in values:
        lines.append(f"        [{lua_quote(value)}] = {lua_quote(translations['de'][value])},")
    lines.extend(["    }", "elseif locale ~= \"ruRU\" then", "    translations = {"])
    for value in values:
        lines.append(f"        [{lua_quote(value)}] = {lua_quote(translations['en'][value])},")
    lines.extend([
        "    }",
        "end",
        "",
        "JP.locale = locale",
        "JP.L = function(text)",
        "    if type(text) ~= \"string\" or not translations then return text end",
        "    return translations[text] or text",
        "end",
        "",
    ])
    (ADDON / "Localization.lua").write_text("\n".join(lines), encoding="utf-8", newline="\n")


def wrap_file(path: Path) -> None:
    source = path.read_text(encoding="utf-8")
    nodes = list(string_nodes(path))
    if not nodes:
        return
    replacements = []
    for node in nodes:
        token = node._first_token
        prefix = source[max(0, token.start - 32):token.start]
        if node.raw in NO_WRAP or re.search(r"\bL\s*\(\s*$", prefix):
            continue
        replacements.append((token.start, token.stop + 1, f"L({source[token.start:token.stop + 1]})"))
    if not replacements:
        return
    for start, stop, replacement in sorted(set(replacements), reverse=True):
        source = source[:start] + replacement + source[stop:]
    if re.search(r"^local L = JP\.L$", source, re.M):
        path.write_text(source, encoding="utf-8", newline="\n")
        return
    namespace = re.search(r"^(local\s+[^\n]*\bJP\s*=\s*\.\.\.\s*)$", source, re.M)
    if not namespace:
        raise RuntimeError(f"cannot find addon namespace in {path}")
    insert = namespace.end()
    source = source[:insert] + "\nlocal L = JP.L" + source[insert:]
    path.write_text(source, encoding="utf-8", newline="\n")


def wrap_sources() -> None:
    for path in sorted(ADDON.rglob("*.lua")):
        if relative(path) in EXCLUDED_FILES or path.name == "Localization.lua":
            continue
        if any(True for _ in string_nodes(path)):
            wrap_file(path)


def main() -> None:
    values = collect()
    print(f"Collected {len(values)} unique strings", flush=True)
    translations = translate_all(values)
    write_locale(values, translations)
    wrap_sources()
    print("Localization.lua and source wrappers generated", flush=True)


if __name__ == "__main__":
    main()
