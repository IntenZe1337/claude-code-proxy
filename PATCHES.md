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
| `start-proxy.cmd` | Windows-start. Sätter `PYTHONUTF8`/`PYTHONIOENCODING` — utan dem blir stdout cp1252 vid omdirigering till fil och processen dör på `UnicodeEncodeError` för pilarna (U+2192) i startbannern. Registreras som schemalagd uppgift `claude-code-proxy`. |
| `deploy/claude-code-proxy.service` | systemd `--user`-unit för Hetzner. |
| `ruff.toml` | Vendorat repo i upstream-stil; kritisk subset (`E9,F63,F7,F82`) som golv, `line-length = 160`. |

`.env` är gitignorerad och innehåller providerns API-nyckel. Se `.env.example`
för formatet.

Senast uppdaterad: 2026-07-26.
