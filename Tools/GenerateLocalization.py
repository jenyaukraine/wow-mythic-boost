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
    r"\|c[0-9a-fA-F]{8}|\|r|\|A:[^|]*\|a|\|T[^|]*\|t|"
    r"%[-+ #0\d.*]*[cdeEfgGiouXxqs]|%%|/mb(?:\s+[A-Za-z]+)*"
)
EXCLUDED_FILES = {"Modules/RealmData.lua"}


MANUAL = {
    "en": {
        "АК": "AF", "СД": "BV", "БН": "DN", "ЗД": "MR",
        "АШ": "VA", "РО": "RLP", "ХС": "TJS", "ГК": "KR",
        "Т": "T", "Х": "H", "Б": "D",
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
        "Автоматически вставлять эпохальный ключ": "Automatically insert Mythic Keystone",
        "Приглашения, эпохальные ключи и умный клик": "Invites, Mythic Keystones and Smart Click",
        "Подземелье и +уровень берутся из камня, режим — «Серьёзный».": "Dungeon and +level come from your Keystone; playstyle is “Serious”.",
        "Зарегистрирован свой ключ +%d, режим «Серьёзный».": "Listed your +%d Keystone with “Serious” playstyle.",
        "Повышение ключа": "Keystone upgrade",
        "Ключ от": "Min key", "Ключ до": "Max key", "Ключей +10 от": "Min +10 keys",
        "Рейтинг от": "Min rating", "Рейтинг до": "Max rating",
        "Не хватает гербов: %d      Золото: %s": "Missing crests: %d      Gold: %s",
        "Улучшать нечего: игра не назвала ни одного герба для надетых вещей.": "Nothing to upgrade: the game returned no crest costs for your equipped items.",
        "Журнал ": "Log ", "Журнал пуст.": "Log is empty.", "Журнал очищен.": "Log cleared.",
        "Журнал выключен. Включить: /mb log on": "Logging is disabled. Enable it with: /mb log on",
        "Журнал ошибок": "Error log", "Журнал ошибок очищен.": "Error log cleared.",
        " будет пересобран после боя.": " will be reloaded after combat.", " пересобран.": " reloaded.",
        "Не удалось пересобрать ": "Failed to reload ",
        "MinimalUI: событие %s недоступно в этом клиенте": "MinimalUI: event %s is unavailable in this client",
        "Клик — снять сумку": "Click — unequip bag",
    },
    "de": {
        "АК": "AF", "СД": "BV", "БН": "DN", "ЗД": "MR",
        "АШ": "VA", "РО": "RLP", "ХС": "TJS", "ГК": "KR",
        "Т": "T", "Х": "H", "Б": "S",
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
        "Автоматически вставлять эпохальный ключ": "Mythischen Schlüsselstein automatisch einfügen",
        "Приглашения, эпохальные ключи и умный клик": "Einladungen, mythische Schlüsselsteine und Smart Click",
        "Подземелье и +уровень берутся из камня, режим — «Серьёзный».": "Dungeon und +Stufe kommen von deinem Schlüsselstein; Spielstil ist „Ernsthaft“.",
        "Зарегистрирован свой ключ +%d, режим «Серьёзный».": "Eigenen +%d-Schlüsselstein mit Spielstil „Ernsthaft“ angemeldet.",
        "Повышение ключа": "Schlüsselstein-Aufwertung",
        "Ключ от": "Schlüssel min.", "Ключ до": "Schlüssel max.", "Ключей +10 от": "+10-Schlüssel min.",
        "Рейтинг от": "Wertung min.", "Рейтинг до": "Wertung max.",
        "Не хватает гербов: %d      Золото: %s": "Fehlende Wappen: %d      Gold: %s",
        "Улучшать нечего: игра не назвала ни одного герба для надетых вещей.": "Nichts aufzuwerten: Das Spiel lieferte keine Wappenkosten für deine angelegten Gegenstände.",
        "Журнал ": "Protokoll ", "Журнал пуст.": "Protokoll ist leer.", "Журнал очищен.": "Protokoll geleert.",
        "Журнал выключен. Включить: /mb log on": "Protokollierung ist deaktiviert. Aktivieren mit: /mb log on",
        "Журнал ошибок": "Fehlerprotokoll", "Журнал ошибок очищен.": "Fehlerprotokoll geleert.",
        " будет пересобран после боя.": " wird nach dem Kampf neu geladen.", " пересобран.": " neu geladen.",
        "Не удалось пересобрать ": "Neuladen fehlgeschlagen: ",
        "MinimalUI: событие %s недоступно в этом клиенте": "MinimalUI: Ereignis %s ist in diesem Client nicht verfügbar",
        "Клик — снять сумку": "Klick — Tasche ablegen",
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
    if re.search(r"^local L = JP\.L$", source, re.M):
        return
    nodes = list(string_nodes(path))
    if not nodes:
        return
    replacements = []
    for node in nodes:
        token = node._first_token
        replacements.append((token.start, token.stop + 1, f"L({source[token.start:token.stop + 1]})"))
    for start, stop, replacement in sorted(set(replacements), reverse=True):
        source = source[:start] + replacement + source[stop:]
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
