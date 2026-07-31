# Lokala avvikelser mot upstream

Fork av [`jodavan/claude-code-proxy`](https://github.com/jodavan/claude-code-proxy).
Den här filen dokumenterar varför `main` här divergerar från upstream, så att
patcharna kan omprövas eller skickas uppströms i stället för att glömmas bort.

Repot körs från `main` på samtliga maskiner (Hetzner, stationär, laptop).
Uppströmssynk sker med `git fetch upstream && git merge upstream/main`.

## Patchar i `proxy.py`

### 1. `normalize_model_name()` — matcha modellnamn med och utan `[1m]`

Claude Code kan skicka modellnamn med suffixet `[1m]` (1M-kontextvarianten).
Utan normalisering matchade inte tier-jämförelsen i `get_provider_config()`,
och begäran föll igenom till riktiga Anthropic i stället för till den
konfigurerade providern.

### 2. `HOST` som miljövariabel — bind till loopback

Upstream hårdkodar `uvicorn.run(app, host="0.0.0.0", ...)`. Proxyn har
providerns API-nyckel inlagd och kräver ingen egen autentisering; på en maskin
utan brandvägg framför exponeras då nyckeln mot hela nätverket. `HOST` läses nu
från miljön med `0.0.0.0` som oförändrad default, och sätts till `127.0.0.1`
i `.env` på alla våra maskiner.

### 3. `passthrough_headers()` — släpp inte igenom transport-headers

Reell bugg i upstream. `httpx` dekomprimerar svarskroppen åt oss, men
`headers=dict(response.headers)` skickade ändå vidare upstreams
`content-encoding: gzip` och `content-length`. Klienten försökte då gunzip:a
klartext och föll — `curl --compressed` gav exit 61 (`CURLE_BAD_CONTENT_ENCODING`)
och `Invoke-RestMethod` gav "unsupported compression method".

Fixen strippar hop-by-hop-headers på båda returvägarna (`/v1/messages`
non-streaming och `/v1/messages/count_tokens`). Streaming-vägen var aldrig
drabbad — den bygger sina egna headers.

Kandidat att skicka uppströms som PR.

## Tillagda filer

| Fil | Syfte |
|---|---|
| `start-proxy.cmd` | Windows-start. Sätter `PYTHONUTF8`/`PYTHONIOENCODING` — utan dem blir stdout cp1252 vid omdirigering till fil och processen dör på `UnicodeEncodeError` för pilarna (U+2192) i startbannern. Dödar även kvarvarande lyssnare på 8082 före start, se nedan. Registreras som schemalagd uppgift `claude-code-proxy`. |
| `deploy/claude-code-proxy.service` | systemd `--user`-unit för Hetzner. |
| `ruff.toml` | Vendorat repo i upstream-stil; kritisk subset (`E9,F63,F7,F82`) som golv, `line-length = 160`. |

`.env` är gitignorerad och innehåller providerns API-nyckel. Se `.env.example`
för formatet.

### `README.md` och `.env.example` speglar inte vår konfiguration

Båda är upstreams original och använder GLM (`glm-4.6`, `glm-4.5-air`) i alla
exempel. Vi kör i stället **DeepSeek V4 Flash** på haiku-tiern, med opus och
sonnet i OAuth-passthrough till riktiga Anthropic.

De lämnas medvetet oförändrade — de är upstream-spårade filer, och lokala
redigeringar i dem ger konflikter vid varje `git merge upstream/main` utan att
tillföra något. Vår faktiska konfiguration finns i `.env` per maskin, och
avvikelserna dokumenteras här.

| | Upstream-exempel | Vår drift |
|---|---|---|
| Haiku | `glm-4.6` via Z.AI | `deepseek-v4-flash` via `api.deepseek.com/anthropic` |
| Opus | `glm-4.5-air` via Z.AI | OAuth-passthrough till Anthropic |
| Sonnet | OAuth-passthrough | OAuth-passthrough till Anthropic |
| `HOST` | `0.0.0.0` (hårdkodat) | `127.0.0.1` via `.env` |

Routningen konfigureras i Claude Codes egen `~/.claude/settings.json` under
`env` (`ANTHROPIC_BASE_URL` + `ANTHROPIC_DEFAULT_HAIKU_MODEL`), inte som
Windows-miljövariabler på användar- eller maskinnivå. Den gäller därför enbart
Claude Code — **inte** Claude Desktops egen chatt, som pratar direkt med
claude.ai och aldrig passerar proxyn.

## Driftfälla på Windows: föräldralös process håller porten

Den schemalagda uppgiften kör som `Gabri` med LogonType S4U, vilket placerar
python-processen i **session 0**. `Stop-ScheduledTask` dödar `cmd`-wrappern men
inte det detacherade python-barnet. Den föräldralösa processen behåller port
8082, den nya instansen kan inte binda och dör direkt — medan den gamla
fortsätter svara på `/health` med **föråldrad** konfiguration. En ändring i
`.env` ser då ut att inte ha tagit, utan att något felmeddelande visas.

Felet är tyst i tre lager samtidigt:

- `Get-ScheduledTaskInfo` visar `LastTaskResult=1`, men uppgiften rapporteras
  ändå som `Running` eftersom wrappern lever.
- `proxy.log` trunkeras av `>`-omdirigeringen vid varje start, medan den gamla
  processen fortsätter skriva på sin egen filoffset — loggen ser färsk ut men
  innehåller den gamla processens banner.
- Från en interaktiv session (session 1, medium integrity) går processen inte
  att döda: både `Stop-Process` och `taskkill /F` ger `Åtkomst nekad`. Manuell
  åtgärd kräver elevering.

`start-proxy.cmd` dödar därför kvarvarande lyssnare på 8082 före start. Det
fungerar utan elevering eftersom skriptet körs i taskens egen session 0-kontext.
Filtret kräver **både** `LISTENING` och `":8082 "`: lyssnarraden har foreign
address `0.0.0.0:0`, så mönstret kan då bara träffa lokal adress. Utan
`LISTENING`-filtret hade etablerade klientanslutningar *mot* proxyn matchat och
anroparen dödats i stället.

Hetzner är inte drabbad — där körs proxyn av en `systemd --user`-unit som
hanterar processträdet korrekt vid `restart`.

Senast uppdaterad: 2026-07-31.
